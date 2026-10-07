# ═══════════════════════════════════════════════════════════════════════════
# test/editor/ClickRoundtripTest.jl
#
# Click round-trip + keyboard-navigation invariants for the Text → Syntax →
# JSON pipeline.
#
# For each example:
#   - test_click_roundtrip walks every character cell in every rendered
#     SegmentCoordinate, fires a MouseClick at the centre of that cell, applies the
#     resulting ReplaceSelectionOperation, re-prints, and asserts that the
#     cursor lands in either the clicked segment's band *or* the immediate
#     neighbour band (the line-boundary case, where the cursor at end of
#     line N is logically identical to cursor at start of line N+1).
#
#   - test_text_navigation_invariants walks a single cursor end to end and asserts the
#     walk is a chain: each step lands on a state not yet visited, and the walk
#     ends by itself at the edge of the text.
# ═══════════════════════════════════════════════════════════════════════════

using ProjecturedKernel.ReferenceModule: get_reference_head, get_reference_tail
using ProjecturedPlatform.TextModule: TextToGraphicsIoMap, SegmentCoordinate

# ── IoMap traversal helpers ────────────────────────────────────────────────

_unwrap(x) = x isa Cell ? x[] : x

function _find_text_iomap(io)
    io isa TextToGraphicsIoMap && return io
    # ChainingIoMap.step_iomaps is a Vector{Cell{IoMap}}; unwrap each.
    # SyntaxCompoundToTextIoMap keeps its expanded children as Cell{Vector{IoMap}}.
    # Either can be absent on a node that has not been expanded.
    for field in (:step_iomaps, :child_iomaps)
        hasfield(typeof(io), field) || continue
        children = _unwrap(getfield(io, field))
        children === nothing && continue
        for c in children
            r = _find_text_iomap(_unwrap(c)); r !== nothing && return r
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

# The x of the character boundary `k` of a segment: the pen position where the
# character after it starts, as the caret stands.
function _segment_x_at(sc::SegmentCoordinate, k::Int, measure::TextMeasure)
    local_pos = k - sc.char_start
    local_pos <= 0 && return sc.x
    offsets = compute_caret_offsets(measure, sc.text, sc.font)
    sc.x + round(Int, offsets[min(local_pos, length(sc.text)) + 1])
end

# True if any step in `path` is a ProjectionReferenceStep. Such paths are valid
# (they encode clicks on projection-introduced characters like delimiters or
# whitespace), but a click that lands *inside* a content segment should NOT
# end up wrapped in a ProjectionReferenceStep — that signals a missing
# domain-level translation step somewhere in the chain.
function _path_contains_projection_reference(path)
    while path isa ConcreteReference
        get_reference_head(path) isa ProjectionReferenceStep && return true
        path = get_reference_tail(path)
    end
    false
end

# ── Click round-trip ───────────────────────────────────────────────────────

# `broken`, when given, is a tuple of error-signature substrings this example is
# known to fail with: if every collected error matches one, the single
# `@test isempty(errors)` is recorded `@test_broken` instead of `@test`, so a
# *new* (unrecognised) click error still surfaces as an unmarked `Fail`.
"""
    test_click_roundtrip(label, document, projection)

For every character cell rendered by `TextToGraphics`, fire a `MouseClick`
inside that cell and assert that the resulting selection makes the cursor
re-appear close to the click. "Close" allows up to one line of vertical
slack to absorb the end-of-line / start-of-next-line cursor-rendering
ambiguity at segment boundaries.
"""
function test_click_roundtrip(label, document, projection; broken=nothing)
    @testset "$label" begin
        clear_selection!(document)
        iomap = print_document(projection, document)
        t2g = _find_text_iomap(iomap)
        if t2g === nothing
            @warn "[$label] no TextToGraphicsIoMap in pipeline; skipping"
            @test true
            return
        end
        coords = t2g.char_to_coord
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
                cx = _segment_x_at(sc, k, measure) + 1
                cy = sc.y + max(1, line_h ÷ 2)
                op = read_intent(projection, iomap, MouseClick(:left, cx, cy, ModifierKeys(); time = 0.0))
                # A click on an inline expand/collapse marker (or a collapsed
                # ellipsis) is a fold gesture, not a cursor move: it yields a
                # ToggleCollapseOperation. That is a legitimate outcome — skip
                # the cursor round-trip for those glyphs.
                op isa ToggleCollapseOperation && continue
                # A click on a link in a rendered view follows the link, and puts
                # no caret: the span of the link shows the hand for it.
                _is_click_roundtrip_link_follow(op) && continue
                if !(op isa ReplaceSelectionOperation)
                    push!(errors, "click ($cx,$cy) span=$(sc.span_path) char=$k produced no ReplaceSelectionOperation")
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
                    push!(errors, "no cursor after click ($cx,$cy) span=$(sc.span_path) char=$k")
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
        if broken !== nothing && !isempty(errors) &&
           all(e -> any(s -> occursin(s, e), broken), errors)
            # @broken: known click-roundtrip failure; see the caller's registry.
            @test_broken isempty(errors)
        else
            for e in errors
                @warn "[$label] $e"
            end
            @test isempty(errors)
        end
    end
end

# ── Keyboard nav invariants ────────────────────────────────────────────────

# The two end-to-end linear cursor walks. Each direction's seed is the other's
# expected terminal state: walking `right` from the text start exhausts at the
# text end, which is exactly where Ctrl+End jumps, and vice versa.
const TEXT_WALK_RIGHT = (name = "right",
                         seed = KeyDown(:home, ModifierKeys(ctrl=true); time = 0.0),
                         step = KeyDown(:right, ModifierKeys(); time = 0.0))
const TEXT_WALK_LEFT  = (name = "left",
                         seed = KeyDown(:end, ModifierKeys(ctrl=true); time = 0.0),
                         step = KeyDown(:left, ModifierKeys(); time = 0.0))

"""
    _walk_cursor(document, projection, walk; max_steps=10_000)

Fire `walk.seed`, then `walk.step` repeatedly, re-printing the document between
moves, until the cursor stops moving. Returns

    (paths, carets, seeded, terminated, cycle, error)

`paths` is the visited selections in visit order, seed first — an ordered
sequence rather than a set, because the two directions are compared as
sequences. `carets` is the rendered caret rect `(x, y)` of each of those states,
which is how the two directions are actually compared: at a span boundary the
same visual caret has two equally valid paths (`(span, len)` and
`(span + 1, 0)`), and `_step_left` / `_step_right` each canonicalize to the one
the *other* direction skips, so the path sequences legitimately differ where the
caret sequences must not.

`terminated` says the walk ended on its own (the reader declined the step, or
the step is a fixed point) rather than by exhausting `max_steps`. `cycle` holds
the offending selection when a step lands on an already-visited state other than
the current one — the walk is then not a chain. `seeded` is false when the seed
gesture yields no selection at all: the pipeline has no cursor to walk, which is
a skip rather than a failure. `error` is set when the printer or a reader threw.
"""
function _walk_cursor(document, projection, walk; max_steps=10_000)
    failure(msg) = (paths=Any[], carets=Any[], seeded=false,
                    terminated=false, cycle=nothing, error=msg)
    partial(paths, carets, msg) = (paths=paths, carets=carets, seeded=true,
                                   terminated=false, cycle=nothing, error=msg)

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
        return (paths=Any[], carets=Any[], seeded=false,
                terminated=false, cycle=nothing, error=nothing)

    paths   = Any[op.path]
    carets  = Any[]
    visited = Set{String}([string(op.path)])
    cycle      = nothing
    terminated = false
    while length(paths) <= max_steps
        current = last(paths)
        clear_selection!(document)
        try
            set_selection!(document, current)
        catch e
            return partial(paths, carets, "set_selection! at [$current] failed: $e")
        end
        iomap = try
            print_document(projection, document)
        catch e
            return partial(paths, carets, "reprint at [$current] failed: $e")
        end
        # Probing the caret forces graphics cells the bare print left lazy, so it
        # is guarded like the print itself.
        caret = try
            _caret_at(iomap)
        catch e
            return partial(paths, carets, "caret probe at [$current] failed: $e")
        end
        push!(carets, caret)
        op = try
            read_intent(projection, iomap, walk.step)
        catch e
            return partial(paths, carets, "reader error at [$current] with $(walk.step): $e")
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
    (paths=paths, carets=carets, seeded=true,
     terminated=terminated, cycle=cycle, error=nothing)
end

# The rendered caret of the state just printed, as (x, y); `nothing` when the
# pipeline renders no caret for it.
function _caret_at(iomap)
    t2g = _find_text_iomap(iomap)
    t2g === nothing && return nothing
    output = t2g.output
    (output === nothing || output.elements === nothing) && return nothing
    rect = _find_cursor_rect(t2g)
    rect === nothing ? nothing : (Int(rect.x), Int(rect.y))
end

# `@test`, or `@test_broken` when this example is known to fail the invariant.
macro test_unless_broken(condition, broken)
    quote
        if $(esc(broken))
            @test_broken $(esc(condition))
        else
            @test $(esc(condition))
        end
    end
end

# The per-direction invariants: the walk runs cleanly, ends on its own, never
# revisits a state, and moves at least once.
function _assert_walk(label, walk, result, broken)
    @testset "$(walk.name)" begin
        result.error === nothing || @warn "[$label] [$(walk.name)] $(result.error)"
        @test_unless_broken(result.error === nothing,
                            Symbol(:walk_, walk.name) in broken)
        result.error === nothing || return
        if !result.seeded
            @warn "[$label] $(walk.seed) produced no selection; skipping the $(walk.name) walk"
            @test true
            return
        end
        result.cycle === nothing ||
            @warn "[$label] [$(walk.name)] revisits [$(result.cycle)]: the walk is not a chain"
        @test result.terminated
        @test_unless_broken(result.cycle === nothing, Symbol(:cycle_, walk.name) in broken)
        @test_unless_broken(length(result.paths) > 1, Symbol(:moved_, walk.name) in broken)
    end
end

# The cross-direction invariants: walking left from the end retraces the
# rightward walk and arrives back at the start.
#
#   :same_length        both walks visit the same number of carets
#   :right_reaches_end  the rightward walk ends where Ctrl+End lands
#   :left_reaches_start the leftward walk ends where Ctrl+Home lands
#
# Exact caret-sequence equality is deliberately *not* asserted. At a line
# boundary the same logical caret renders in two places — the end of line N and
# the start of line N+1 — and the two directions canonicalize to different ones
# (see `_step_left` / `_step_right`), so the caret sequences agree only for
# single-line texts. `test_click_roundtrip` tolerates the same ambiguity with
# its one-band `dy` slack.
function _assert_walks_agree(label, right, left, broken)
    @testset "right ↔ left" begin
        for result in (right, left)
            (result.error === nothing && result.seeded) || return  # already reported
        end
        carets(result) = count(!isnothing, result.carets)
        same_length = length(right.paths) == length(left.paths)
        same_length || @warn "[$label] the leftward walk visits $(length(left.paths)) carets, \
                              the rightward walk $(length(right.paths)) \
                              (rendered: $(carets(left)) vs $(carets(right)))"
        @test_unless_broken same_length (:same_length in broken)
        @test_unless_broken(string(last(right.paths)) == string(first(left.paths)),
                            :right_reaches_end in broken)
        @test_unless_broken(string(last(left.paths)) == string(first(right.paths)),
                            :left_reaches_start in broken)
    end
end

"""
    test_text_navigation_invariants(label, document, projection;
                             directions=(:right, :left), broken=())

Walk a single cursor end to end in both directions and assert the two walks
describe the same caret chain. Each walk on its own must be a chain — every step
lands on a state not yet visited, and the walk ends by itself at the edge of the
text — and together they must agree: same number of carets, each direction
ending where the other's seed gesture lands.

`directions` runs a single walk in isolation (`(:right,)`) while debugging.
`broken` names the invariants this example is known to fail, and marks them
`@test_broken` rather than `@test`: `:walk_right` / `:walk_left` for a walk that
cannot run at all (the printer or a reader throws), `:cycle_right` / `:cycle_left`
for a walk that revisits a caret (not a chain), `:moved_right` / `:moved_left`
for a walk that never gets past its seed caret, and `:same_length` /
`:right_reaches_end` / `:left_reaches_start` for the cross-direction ones.
"""
function test_text_navigation_invariants(label, document, projection;
                                  directions=(:right, :left), broken=())
    @testset "$label" begin
        results = Dict{Symbol,Any}()
        for direction in directions
            walk = direction === :right ? TEXT_WALK_RIGHT :
                   direction === :left  ? TEXT_WALK_LEFT  :
                   throw(ArgumentError("unknown walk direction $direction"))
            results[direction] = _walk_cursor(document, projection, walk)
            _assert_walk(label, walk, results[direction], broken)
        end
        if haskey(results, :right) && haskey(results, :left)
            _assert_walks_agree(label, results[:right], results[:left], broken)
        end
    end
end

# The `Example`-typed overload and the sweep (`test_text_navigation_invariants_all`)
# live in the `ProjecturedTest` umbrella; the JSON content-click checks live
# beside the JSON domain (JsonContentClicksTest.jl, → domain-test in phase 3).

# The `Example`-typed overloads; the sweeps stay in the umbrella.
test_click_roundtrip(example::Example) =
    test_click_roundtrip(example.name, example.document, example.projection)

test_text_navigation_invariants(example::Example; directions=(:right, :left), broken=()) =
    test_text_navigation_invariants(example.name, example.document, example.projection;
                             directions=directions, broken=broken)

# Whether a click answered the open of the target of a link.
_is_click_roundtrip_link_follow(operation::OpenPageOperation) = operation.target !== nothing
_is_click_roundtrip_link_follow(operation::CompoundOperation) =
    any(_is_click_roundtrip_link_follow, operation.operations)
_is_click_roundtrip_link_follow(operation::WrappingOperation) =
    _is_click_roundtrip_link_follow(get_wrapped_operation(operation))
_is_click_roundtrip_link_follow(::Any) = false
