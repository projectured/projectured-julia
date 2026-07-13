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
#   - test_text_nav_invariants walks a single cursor end to end and asserts the
#     walk is a chain: each step lands on a state not yet visited, and the walk
#     ends by itself at the edge of the text.
# ═══════════════════════════════════════════════════════════════════════════

using ProjecturedKernel.ReferenceModule: head, tail
using ProjecturedVisual.TextToGraphicsModule: TextToGraphicsIoMap, SegCoord

# ── IoMap traversal helpers ────────────────────────────────────────────────

function _find_text_iomap(io)
    io isa TextToGraphicsIoMap && return io
    # ChainingProjectionIoMap.step_iomaps is a Vector{Cell{IoMap}}; unwrap each.
    if hasfield(typeof(io), :step_iomaps)
        for s in io.step_iomaps
            r = _find_text_iomap(s isa Cell ? s[] : s); r !== nothing && return r
        end
    end
    # SyntaxNodeToTextIoMap keeps its expanded children as Cell{Vector{IoMap}}.
    if hasfield(typeof(io), :child_iomaps)
        for c in (io.child_iomaps isa Cell ? io.child_iomaps[] : io.child_iomaps)
            r = _find_text_iomap(c isa Cell ? c[] : c); r !== nothing && return r
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

# The two end-to-end linear cursor walks. Each direction's seed is the other's
# expected terminal state: walking `right` from the text start exhausts at the
# text end, which is exactly where Ctrl+End jumps, and vice versa.
const TEXT_WALK_RIGHT = (name = "right",
                         seed = KeyDown(:home, Modifiers(ctrl=true)),
                         step = KeyDown(:right, Modifiers()))
const TEXT_WALK_LEFT  = (name = "left",
                         seed = KeyDown(:end, Modifiers(ctrl=true)),
                         step = KeyDown(:left, Modifiers()))

"""
    _walk_cursor(document, projection, walk; max_steps=10_000)

Fire `walk.seed`, then `walk.step` repeatedly, re-printing the document between
moves, until the cursor stops moving. Returns

    (paths, seeded, terminated, cycle, error)

`paths` is the visited selections in visit order, seed first — an ordered
sequence rather than a set, because the two directions are compared as
sequences. `terminated` says the walk ended on its own (the reader declined the
step, or the step is a fixed point) rather than by exhausting `max_steps`.
`cycle` holds the offending selection when a step lands on an already-visited
state other than the current one — the walk is then not a chain. `seeded` is
false when the seed gesture yields no selection at all: the pipeline has no
cursor to walk, which is a skip rather than a failure. `error` is set when the
printer or a reader threw.
"""
function _walk_cursor(document, projection, walk; max_steps=10_000)
    failure(msg) = (paths=Any[], seeded=false, terminated=false, cycle=nothing, error=msg)

    clear_selection!(document)
    iomap = try
        print_document(projection, document)
    catch e
        return failure("print_document failed: $e")
    end
    op = try
        read_intent(projection, iomap, walk.seed)
    catch e
        return failure("seed $(walk.seed) failed: $e")
    end
    # No cursor at the top of this pipeline: nothing to walk.
    op isa ReplaceSelectionOperation ||
        return (paths=Any[], seeded=false, terminated=false, cycle=nothing, error=nothing)

    paths   = Any[op.path]
    visited = Set{String}([string(op.path)])
    cycle      = nothing
    terminated = false
    while length(paths) <= max_steps
        current = last(paths)
        clear_selection!(document)
        try
            set_selection!(document, current)
        catch e
            return (paths=paths, seeded=true, terminated=false, cycle=nothing,
                    error="set_selection! at [$current] failed: $e")
        end
        iomap = try
            print_document(projection, document)
        catch e
            return (paths=paths, seeded=true, terminated=false, cycle=nothing,
                    error="reprint at [$current] failed: $e")
        end
        op = try
            read_intent(projection, iomap, walk.step)
        catch e
            return (paths=paths, seeded=true, terminated=false, cycle=nothing,
                    error="reader error at [$current] with $(walk.step): $e")
        end
        if !(op isa ReplaceSelectionOperation)
            terminated = true          # the reader declines: the edge of the text
            break
        end
        key = string(op.path)
        if key == string(current)
            terminated = true          # a fixed point: the edge of the text
            break
        end
        if key in visited
            cycle = key                # revisits an earlier state: not a chain
            terminated = true
            break
        end
        push!(visited, key)
        push!(paths, op.path)
    end
    (paths=paths, seeded=true, terminated=terminated, cycle=cycle, error=nothing)
end

# The per-direction invariants: the walk runs cleanly, ends on its own, never
# revisits a state, and moves at least once.
function _assert_walk(label, walk, result)
    @testset "$(walk.name)" begin
        result.error === nothing || @warn "[$label] [$(walk.name)] $(result.error)"
        @test result.error === nothing
        result.error === nothing || return
        if !result.seeded
            @warn "[$label] $(walk.seed) produced no selection; skipping the $(walk.name) walk"
            @test true
            return
        end
        result.cycle === nothing ||
            @warn "[$label] [$(walk.name)] revisits [$(result.cycle)]: the walk is not a chain"
        @test result.terminated
        @test result.cycle === nothing
        @test length(result.paths) > 1
    end
end

"""
    test_text_nav_invariants(label, document, projection; directions=(:right,))

Walk a single cursor end to end and assert it describes a chain: every step
lands on a state not yet visited, and the walk ends by itself at the edge of the
text. `directions` selects which walks run — `:right` from Ctrl+End's mirror
(Ctrl+Home) rightwards, `:left` from Ctrl+End leftwards.
"""
function test_text_nav_invariants(label, document, projection; directions=(:right,))
    @testset "$label" begin
        for direction in directions
            walk = direction === :right ? TEXT_WALK_RIGHT :
                   direction === :left  ? TEXT_WALK_LEFT  :
                   throw(ArgumentError("unknown walk direction $direction"))
            _assert_walk(label, walk, _walk_cursor(document, projection, walk))
        end
    end
end

# The `Example`-typed overload and the sweep (`test_text_nav_invariants_all`)
# live in the `ProjecturedTest` umbrella; the JSON content-click checks live
# beside the JSON domain (JsonContentClicksTest.jl, → domain-test in phase 3).

# The `Example`-typed overloads; the sweeps stay in the umbrella.
test_click_roundtrip(example::Example) =
    test_click_roundtrip(example.name, example.document, example.projection)

test_text_nav_invariants(example::Example; directions=(:right,)) =
    test_text_nav_invariants(example.name, example.document, example.projection;
                             directions=directions)
