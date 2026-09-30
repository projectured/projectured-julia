# WidgetTree light feedback + click-to-collapse/expand.
#
# The tree renders a faint band behind the row that its own mouse target names: a
# move writes the path of the part under the pointer, and the band follows
# whatever row that path resolves to. It also toggles a parent's children when
# its chevron is clicked. Here we drive the WidgetTree projection directly with a
# deterministic text measure so row geometry is exact.

using ProjecturedKernel.CellModule: Cell, Computation, is_cell_up_to_date

function test_widget_tree()
@testset "WidgetTree hover + collapse" begin

# Deterministic measure ⇒ row_height = 16 + 2*4 = 24, indent 22, chevron column 18.
_det = FixedMeasure(8, 12, 4, 0)
_w2g = WidgetToGraphics(font_ubuntu_regular_20; measure = _det)
_treeproj = nothing
for (T, pr) in _w2g.dispatch
    T === WidgetTree && (_treeproj = pr)
end
@test _treeproj !== nothing

_mods = ModifierKeys()
_readop_marked(io, g, route = nothing) = begin
    ch = read_intent(_treeproj, nothing, Intent(g, nothing, "", "", route), io)
    ch isa Intent ? ch.operation : ch
end
# The answer, looking through the mark a hover carries as view state.
_readop(io, g, route = nothing) = (op = _readop_marked(io, g, route);
                                   op isa ReplaceViewStateOperation ? get_wrapped_operation(op) : op)
# A hover and a leave, as the mouse target tracking gives them; the route says
# where they go.
_hover = MouseHover(0, 0, MouseButtons(), _mods; time = 0.0)
_leave = MouseLeave(0, 0, MouseButtons(), _mods; time = 0.0)
_node(path) = WidgetModule._wtree_path_ref(path)
_fresh() = begin
    w = WidgetTree(Any[("src", Any["a.jl", "b.jl"]), "README"]; expanded = Set([[1]]))
    (w, print_document(_treeproj, w))
end
# Whether the node at `path` has children. A row holds no node, so this reads it.
_has_children(w, path) = WidgetModule._wtree_has_children(WidgetModule._wtree_node_at(w, path))
# The canvas of the rows, and the bands of row `k`: each row draws its own.
_rows_canvas(io) = only(el for el in io.output.elements
                        if el isa GraphicsCanvas && el.layout == layout_vertical)
_bands(io, k) = [r for r in _rows_canvas(io).elements[k].elements
                 if r isa GraphicsRect && r.color.alpha[] > 0]
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

@testset "a node is closed until its path is in expanded" begin
    w = WidgetTree(Any[("src", Any["a.jl", "b.jl"]), "README"])
    geom = print_document(_treeproj, w).geometry
    @test [r.path for r in geom.rows] == [[1], [2]]    # src and README, src closed
    @test _has_children(w, [1]) && !([1] in w.expanded)
end

@testset "flatten records rows, chevron box, and open flag" begin
    w, io = _fresh()
    geom = io.geometry
    @test length(geom.rows) == 4                       # src, a.jl, b.jl, README
    @test [r.path for r in geom.rows] == [[1], [1, 1], [1, 2], [2]]
    @test _has_children(w, [1]) && [1] in w.expanded
    @test !_has_children(w, [2])                       # README is a leaf
    @test geom.rows[1].chevron_x0 == 0 && geom.rows[1].chevron_x1 == 18
    @test geom.rows[2].chevron_x0 == 22                # indented one level
end

@testset "a move onto a row makes it the part under the pointer; moving off it clears it" begin
    w, io = _fresh()
    driver = MttDriver(_treeproj, w)
    r1 = io.geometry.rows[1]
    r2 = io.geometry.rows[2]

    _mtt_move!(driver, r1.chevron_x1 + 5, r1.y0 + 2, 1.0)
    @test WidgetModule._wtree_ref_path(get_mouse_target(w)) == [1]

    # A different row becomes the part under the pointer instead.
    _mtt_move!(driver, r2.chevron_x1 + 5, r2.y0 + 2, 1.1)
    @test WidgetModule._wtree_ref_path(get_mouse_target(w)) == [1, 1]

    # The tree's own reader never answers a crossing or a motion: the light
    # comes only from the mouse target that the tracking writes.
    @test _readop(io, _hover, _node([1])) === nothing
    @test _readop(io, _leave, _node([1])) === nothing
    @test _readop(io, MouseMove(r1.chevron_x1 + 5, r1.y0 + 5, MouseButtons(), _mods; time = 0.0)) === nothing

    # The leave of the window clears it.
    _mtt_leave!(driver, 1.2)
    @test get_mouse_target(w) === nothing
end

@testset "clicking a chevron collapses/expands; clicking a label selects" begin
    w, io = _fresh()
    r1 = io.geometry.rows[1]
    # Chevron click on the open parent → close it (children hidden).
    op = _readop(io, MouseClick(:left, (r1.chevron_x0 + r1.chevron_x1) ÷ 2, r1.y0 + 2, _mods; time = 0.0))
    @test op isa ReplaceReferencedValueOperation
    # A folded row is view state, so a history does not record the click.
    @test _readop_marked(io, MouseClick(:left, (r1.chevron_x0 + r1.chevron_x1) ÷ 2, r1.y0 + 2, _mods; time = 0.0)) isa
          ReplaceViewStateOperation
    getfield(w, :expanded)[] = op.value
    @test !([1] in w.expanded)
    g = io.geometry
    @test length(g.rows) == 2
    # Chevron click again → open.
    op = _readop(io, MouseClick(:left, (r1.chevron_x0 + r1.chevron_x1) ÷ 2, r1.y0 + 2, _mods; time = 0.0))
    getfield(w, :expanded)[] = op.value
    @test [1] in w.expanded
    @test length(io.geometry.rows) == 4

    # A click on the label (past the chevron column) selects instead of toggling.
    w2, io2 = _fresh()
    r = io2.geometry.rows[1]
    op = _readop(io2, MouseClick(:left, r.chevron_x1 + 20, r.y0 + 2, _mods; time = 0.0))
    @test op isa ReplaceSelectionOperation
end

@testset "each row draws its light band and its selection band" begin
    w, io = _fresh()
    bands = _bands(io, 1)
    @test length(bands) == 2                            # light + selection bands
    @test all(Int(r.h[]) == 0 for r in bands)           # neither active yet
    # Row 1 the part under the pointer → one of its bands gains the row's height.
    getfield(w, :mouse_target)[] = _node([1])
    @test any(Int(r.h[]) == 24 for r in _bands(io, 1))
    @test all(Int(r.h[]) == 0 for r in _bands(io, 2))   # the next row stays dark
end

@testset "a toggle keeps the canvas of each row that stays, and changes only its chevron" begin
    w = WidgetTree(Any[("src", Any["a.jl", "b.jl"]), ("doc", Any["c.md"]), "README"];
                   expanded = Set{Vector{Int}}())
    io = print_document(_treeproj, w)
    right = string(WidgetModule.find_icon_character(:chevron_right))
    down = string(WidgetModule.find_icon_character(:chevron_down))
    chevron(row) = only(e for e in row.elements if e isa GraphicsText && e.text in (right, down))
    before = collect(_rows_canvas(io).elements)
    @test length(before) == 3
    @test chevron(before[1]).text == right
    doc_chevron = chevron(before[2])

    getfield(w, :expanded)[] = Set([[1]])
    # The content of a folder row that did not toggle is not computed again: only
    # the glyph of its chevron reads the set of open folders.
    @test is_cell_up_to_date(getfield(getfield(before[2], :elements)[], :elements))
    @test !is_cell_up_to_date(getfield(doc_chevron, :text))
    # The rows of the folder are new, the rows that stay keep their canvas, and
    # the rows under the folder move down by its two rows.
    after = collect(_rows_canvas(io).elements)
    @test length(after) == 5
    @test after[1] === before[1] && after[4] === before[2] && after[5] === before[3]
    @test Int(after[4].y) == 3 * 24
    @test chevron(after[1]).text == down
    @test doc_chevron.text == right
end

@testset "the whole tree canvas is a hit target (nested routability)" begin
    w, io = _fresh()
    _ = io.geometry
    # A transparent full-canvas rect makes the tree hittable over empty row space
    # when nested in a container that gates on hit_element_at.
    hit = [r for r in _rects(io) if r.color.alpha[] == 0]
    @test length(hit) == 1
    @test Int(hit[1].w[]) == io.width && Int(hit[1].h[]) == io.geometry.total_h
end

# A tree nested in a layout / tabbed pane / shell must still light under the
# pointer and take a click: a point maps backward through the containers to the
# node, and the hover goes to the tree by route.
@testset "the light and a click reach a tree nested in containers" begin
    _full = make_widget_projection_example(measure = _det)
    _tree() = WidgetTree(Any[
        WidgetTreeNode(:folder, "src", Any[WidgetTreeNode(:file, "a.jl")]),
        WidgetTreeNode(:file, "README")])
    # Count grid points where a move lights the tree and a click selects in it.
    function reach(tree, doc; xs, ys)
        io = print_document(_full, doc)
        driver = MttDriver(_full, doc)
        lit = clicks = 0
        time = 0.0
        for x in xs, y in ys
            _mtt_move!(driver, x, y, time += 0.01)
            get_mouse_target(tree) !== nothing && (lit += 1)
            cp = read_intent(_full, nothing, Intent(MouseClick(:left, x, y, _mods; time = 0.0), nothing), io)
            op = cp isa Intent ? cp.operation : cp
            op isa ReplaceSelectionOperation && (clicks += 1)
        end
        (lit, clicks)
    end
    for wrap in (tree -> VerticalLayout(Any[tree]),
                 tree -> WidgetTabbedPane([("Data", VerticalLayout(Any[tree]))]),
                 tree -> WidgetShell(WidgetTabbedPane([("Data", VerticalLayout(Any[tree]))]);
                                     size = Point2D(400, 300)))
        tree = _tree()
        e, c = reach(tree, wrap(tree); xs = 0:6:240, ys = 0:6:200)
        @test e > 0     # a move lights a row of the tree
        @test c > 0     # MouseClick selects a tree node through the container
    end
end

end # @testset
end # function
