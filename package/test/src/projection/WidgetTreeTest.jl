# WidgetTree hover feedback + click-to-collapse/expand.
#
# The tree renders a faint hover band behind the row under the pointer (driven by
# `MouseEnter`/`MouseMove`/`MouseLeave` crossings, which the
# `WidgetHoverTrackingProjection` synthesises from motion) and toggles a parent's
# children when its chevron is clicked. Both reuse the same `geom.rows` hit-test as
# selection, so they are coordinate-space-agnostic. Here we drive the WidgetTree
# projection directly with a deterministic text measure so row geometry is exact.

using Projectured: WidgetTree, WidgetTreeNode, WidgetToGraphics, VerticalLayout,
    WidgetTabbedPane, WidgetShell, Point2D, Intent,
    MousePress, MouseEnter, MouseMove, MouseLeave, Modifiers,
    ReplaceReferencedValueOperation, ReplaceSelectionOperation,
    GraphicsRect, font_ubuntu_regular_20, print_document, read_intent
using Projectured.CellModule: Cell

function test_widget_tree()
@testset "WidgetTree hover + collapse" begin

# Deterministic measure ⇒ row_height = 16 + 2*4 = 24, indent 22, chevron column 18.
_det = (t, f) -> (length(t) * 8, 16)
_w2g = WidgetToGraphics(font_ubuntu_regular_20; measure = _det)
_treeproj = nothing
for (T, pr) in _w2g.dispatch
    T === WidgetTree && (_treeproj = pr)
end
@test _treeproj !== nothing

_mods = Modifiers()
_readop(io, g) = begin
    ch = read_intent(_treeproj, nothing, Intent(g, nothing), io)
    ch isa Intent ? ch.operation : ch
end
_fresh() = begin
    w = WidgetTree(Point2D(0, 0), Any[("src", Any["a.jl", "b.jl"]), "README"])
    (w, print_document(_treeproj, w))
end
# GraphicsRect overlays in the canvas (the hover + selection bands). Canvas
# elements may be raw graphics or Cell-wrapped, so unwrap defensively.
function _rects(io)
    out = GraphicsRect[]
    for el in io.output.elements
        el = el isa Cell ? el[] : el
        el isa GraphicsRect && push!(out, el)
    end
    out
end

@testset "flatten records rows, chevron box, and collapse flag" begin
    w, io = _fresh()
    geom = io.geometry[]
    @test length(geom.rows) == 4                       # src, a.jl, b.jl, README
    @test [r.path for r in geom.rows] == [[1], [1, 1], [1, 2], [2]]
    @test geom.rows[1].has_children && !geom.rows[1].collapsed
    @test !geom.rows[4].has_children                   # README is a leaf
    @test geom.rows[1].chevron_x0 == 0 && geom.rows[1].chevron_x1 == 18
    @test geom.rows[2].chevron_x0 == 22                # indented one level
end

@testset "MouseEnter sets the hovered row; a leave clears it" begin
    w, io = _fresh()
    r1 = io.geometry[].rows[1]
    op = _readop(io, MouseEnter(r1.chevron_x1 + 2, r1.y0 + 2, :none, _mods))
    @test op isa ReplaceReferencedValueOperation && op.value !== nothing
    getfield(w, :hovered)[] = op.value
    @test w.hovered !== nothing

    op = _readop(io, MouseLeave(0, 0, :none, _mods))
    @test op isa ReplaceReferencedValueOperation && op.value === nothing
    getfield(w, :hovered)[] = op.value
    @test w.hovered === nothing
    # A leave with nothing already hovered is a no-op.
    @test _readop(io, MouseLeave(0, 0, :none, _mods)) === nothing
end

@testset "MouseMove updates hover only when the row changes" begin
    w, io = _fresh()
    rows = io.geometry[].rows
    r1, r2 = rows[1], rows[2]
    getfield(w, :hovered)[] = _readop(io, MouseEnter(r1.chevron_x1 + 2, r1.y0 + 2, :none, _mods)).value
    # Same row again → nothing (no churn).
    @test _readop(io, MouseMove(r1.chevron_x1 + 5, r1.y0 + 5, :none, _mods)) === nothing
    # Different row → a fresh write.
    op = _readop(io, MouseMove(r2.chevron_x1 + 5, r2.y0 + 5, :none, _mods))
    @test op isa ReplaceReferencedValueOperation && op.value !== nothing
end

@testset "clicking a chevron collapses/expands; clicking a label selects" begin
    w, io = _fresh()
    r1 = io.geometry[].rows[1]
    # Chevron click on the parent → collapse (children hidden, flag set).
    op = _readop(io, MousePress(:left, (r1.chevron_x0 + r1.chevron_x1) ÷ 2, r1.y0 + 2, _mods))
    @test op isa ReplaceReferencedValueOperation
    getfield(w, :collapsed)[] = op.value
    @test [1] in w.collapsed
    g = io.geometry[]
    @test length(g.rows) == 2 && g.rows[1].collapsed
    # Chevron click again → expand.
    op = _readop(io, MousePress(:left, (r1.chevron_x0 + r1.chevron_x1) ÷ 2, r1.y0 + 2, _mods))
    getfield(w, :collapsed)[] = op.value
    @test !([1] in w.collapsed)
    @test length(io.geometry[].rows) == 4

    # A click on the label (past the chevron column) selects instead of toggling.
    w2, io2 = _fresh()
    r = io2.geometry[].rows[1]
    op = _readop(io2, MousePress(:left, r.chevron_x1 + 20, r.y0 + 2, _mods))
    @test op isa ReplaceSelectionOperation
end

# Only the translucent bands (alpha > 0); excludes the invisible whole-canvas hit
# target, which is always full-height.
_bands(io) = [r for r in _rects(io) if r.color.alpha[] > 0]

@testset "hover band overlay tracks w.hovered" begin
    w, io = _fresh()
    _ = io.geometry[]
    bands = _bands(io)
    @test length(bands) == 2                            # hover + selection bands
    @test all(Int(r.h[]) == 0 for r in bands)           # neither active yet
    # Hover row 1 → one band gains the row's height.
    getfield(w, :hovered)[] = _readop(io, MouseEnter(2, io.geometry[].rows[1].y0 + 2, :none, _mods)).value
    @test any(Int(r.h[]) == 24 for r in _bands(io))
end

@testset "the whole tree canvas is a hit target (nested routability)" begin
    w, io = _fresh()
    _ = io.geometry[]
    # A transparent full-canvas rect makes the tree hittable over empty row space
    # when nested in a container that gates on hit_element_at.
    hit = [r for r in _rects(io) if r.color.alpha[] == 0]
    @test length(hit) == 1
    @test Int(hit[1].w[]) == io.geometry[].total_w && Int(hit[1].h[]) == io.geometry[].total_h
end

# Regression: a tree nested in a layout / tabbed pane / shell must still receive
# the pointer. Containers used to route MouseEnter/MouseMove/MouseLeave via the
# coordless, selection-only path (so a hovered tree in a tab stayed unlit), and the
# tree's gesture logic lived only in the 4-arg reader (which containers don't call).
@testset "crossings + clicks reach a tree nested in containers" begin
    _full = make_widget_projection_example(measure = _det)
    _tree() = WidgetTree(Point2D(0, 0), Any[
        WidgetTreeNode(:folder, "src", Any[WidgetTreeNode(:file, "a.jl")]),
        WidgetTreeNode(:file, "README")])
    # Count grid points whose MouseEnter / MousePress reach the tree.
    function reach(doc; xs, ys)
        io = print_document(_full, doc)
        enters = clicks = 0
        for x in xs, y in ys
            ce = read_intent(_full, nothing, Intent(MouseEnter(x, y, :none, _mods), nothing), io)
            oe = ce isa Intent ? ce.operation : ce
            oe isa ReplaceReferencedValueOperation && oe.document isa WidgetTree && (enters += 1)
            cp = read_intent(_full, nothing, Intent(MousePress(:left, x, y, _mods), nothing), io)
            op = cp isa Intent ? cp.operation : cp
            op isa ReplaceSelectionOperation && (clicks += 1)
        end
        (enters, clicks)
    end
    for doc in (VerticalLayout(Any[_tree()]),
                WidgetTabbedPane([("Data", VerticalLayout(Any[_tree()]))]),
                WidgetShell(WidgetTabbedPane([("Data", VerticalLayout(Any[_tree()]))]);
                            size = Point2D(400, 300)))
        e, c = reach(doc; xs = 0:6:240, ys = 0:6:200)
        @test e > 0     # MouseEnter reaches the tree (was 0 before the fix)
        @test c > 0     # MousePress selects a tree node through the container
    end
end

end # @testset
end # function
