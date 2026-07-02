# WidgetTree hover feedback + click-to-collapse/expand.
#
# The tree renders a faint hover band behind the row under the pointer (driven by
# `MouseEnter`/`MouseMove`/`MouseLeave` crossings, which the
# `WidgetHoverTrackingProjection` synthesises from motion) and toggles a parent's
# children when its chevron is clicked. Both reuse the same `geom.rows` hit-test as
# selection, so they are coordinate-space-agnostic. Here we drive the WidgetTree
# projection directly with a deterministic text measure so row geometry is exact.

using Projectured: WidgetTree, WidgetToGraphics, Point2D, Change,
    MousePress, MouseEnter, MouseMove, MouseLeave, Modifiers,
    ReplaceReferencedValue, ReplaceSelectionOperation,
    GraphicsRect, font_ubuntu_regular_20, projection_print, projection_read
using Projectured.ReactiveModule: Cell

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
    ch = projection_read(_treeproj, nothing, Change(g, nothing), io)
    ch isa Change ? ch.operation : ch
end
_fresh() = begin
    w = WidgetTree(Point2D(0, 0), Any[("src", Any["a.jl", "b.jl"]), "README"])
    (w, projection_print(_treeproj, w))
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
    @test op isa ReplaceReferencedValue && op.value !== nothing
    getfield(w, :hovered)[] = op.value
    @test w.hovered !== nothing

    op = _readop(io, MouseLeave(0, 0, :none, _mods))
    @test op isa ReplaceReferencedValue && op.value === nothing
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
    @test op isa ReplaceReferencedValue && op.value !== nothing
end

@testset "clicking a chevron collapses/expands; clicking a label selects" begin
    w, io = _fresh()
    r1 = io.geometry[].rows[1]
    # Chevron click on the parent → collapse (children hidden, flag set).
    op = _readop(io, MousePress(:left, (r1.chevron_x0 + r1.chevron_x1) ÷ 2, r1.y0 + 2, _mods))
    @test op isa ReplaceReferencedValue
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

@testset "hover band overlay tracks w.hovered" begin
    w, io = _fresh()
    _ = io.geometry[]
    rects = _rects(io)
    @test length(rects) == 2                            # hover + selection bands
    @test all(Int(r.h[]) == 0 for r in rects)           # neither active yet
    # Hover row 1 → one band gains the row's height.
    getfield(w, :hovered)[] = _readop(io, MouseEnter(2, io.geometry[].rows[1].y0 + 2, :none, _mods)).value
    @test any(Int(r.h[]) == 24 for r in _rects(io))
end

end # @testset
end # function
