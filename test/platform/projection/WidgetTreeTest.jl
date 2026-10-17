# WidgetTree light feedback + click-to-collapse/expand.
#
# The tree renders a faint band behind the row that its own mouse target names: a
# move writes the path of the part under the pointer, and the band follows
# whatever row that path resolves to. It also toggles a parent's children when
# its chevron is clicked. Here we drive the WidgetTree projection directly with a
# deterministic text measure so row geometry is exact.

using ProjecturedKernel.CellModule: Cell, Computation, is_cell_valid
using ProjecturedKernel.SelectionModule: replace_selection!, get_selection
using ProjecturedKernel.ReferenceModule: evaluate_reference

function test_widget_tree()
@testset "WidgetTree hover + collapse" begin

# Deterministic measure ⇒ row_height = 16 + 2*2 = 20, indent 12, chevron column 16.
_det = FixedMeasure(8, 12, 4, 0)
_w2g = WidgetToGraphics(StyleFont("Ubuntu", 20); measure = _det)
_treeproj = nothing
for (T, pr) in _w2g.dispatch
    T === WidgetTree && (_treeproj = pr)
end
@test _treeproj !== nothing

_mods = ModifierKeys()
_readop_marked(io, g) = begin
    ch = read_intent(_treeproj, nothing, Intent(g, nothing), io)
    ch isa Intent ? ch.operation : ch
end
# The answer, looking through the mark a hover carries as view state.
_readop(io, g) = (op = _readop_marked(io, g);
                  op isa ReplaceViewStateOperation ? get_wrapped_operation(op) : op)
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

@testset "the path of the child of a tuple node is a selection the tree takes" begin
    w, _ = _fresh()
    replace_selection!(w, _node([1, 2]))
    @test evaluate_reference(w, get_selection(w)) == "b.jl"
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
    @test geom.rows[1].chevron_x0 == 0 && geom.rows[1].chevron_x1 == 16
    @test geom.rows[2].chevron_x0 == 12                # indented one level
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

    # The tree's own reader never answers a motion: the light comes only from
    # the mouse target that a move writes.
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
    @test any(Int(r.h[]) == 20 for r in _bands(io, 1))
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
    @test is_cell_valid(getfield(getfield(before[2], :elements)[], :elements))
    @test !is_cell_valid(getfield(doc_chevron, :text))
    # The rows of the folder are new, the rows that stay keep their canvas, and
    # the rows under the folder move down by its two rows.
    after = collect(_rows_canvas(io).elements)
    @test length(after) == 5
    @test after[1] === before[1] && after[4] === before[2] && after[5] === before[3]
    @test Int(after[4].y) == 3 * 20
    @test chevron(after[1]).text == down
    @test doc_chevron.text == right
end

@testset "a node that answers whether it has children reads no children while it is closed" begin
    reads = Ref(0)
    counted(names...) = CellVector(@computation((reads[] += 1; Any[names...])); element = name -> name)
    full = WidgetTreeNode("", "full", counted("a", "b"); has_children = () -> true)
    empty = WidgetTreeNode("", "empty", counted("c"); has_children = () -> false)
    w = WidgetTree(Any[full, empty]; expanded = Set{Vector{Int}}())
    io = print_document(_treeproj, w)
    marks = (string(WidgetModule.find_icon_character(:chevron_right)),
             string(WidgetModule.find_icon_character(:chevron_down)))
    chevrons(row) = [e for e in row.elements if e isa GraphicsText && e.text in marks]
    rows = collect(_rows_canvas(io).elements)
    @test length(chevrons(rows[1])) == 1 && isempty(chevrons(rows[2]))
    @test reads[] == 0
    # An open node reads its children, to draw the rows under it.
    getfield(w, :expanded)[] = Set([[1]])
    @test length(_rows_canvas(io).elements) == 4
    @test reads[] == 1
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

# A tree that prints as the rows of its own pane makes its rows as a lazy list: a
# walk from the head, as the renderer and the readers walk, makes each row that it
# reaches and no other.
_print_tree_rows(w; width = 300, height = 200) =
    print_document(_treeproj, _w2g, w,
                   ProjecturedKernel.ProjectionModule.with_property(
                       ProjecturedKernel.ProjectionModule.with_exact_size(
                           PrinterContext(); width = Cell(Int32(width)), height = Cell(Int32(height))),
                       :rows_of, w))

# The count of the rows that a walk down `height` pixels from the head reaches.
function _walk_tree_rows(io, height)
    link, walked = _rows_canvas(io).elements, 0
    while link !== nothing && Int(link.value.y) < height
        (link, walked) = (link.next, walked + 1)
    end
    walked
end

@testset "a tree that scrolls itself makes only the rows that a walk reaches" begin
    made = Ref(0)
    runs = make_index_list(10_000_000, 1, k -> (made[] += 1; WidgetTreeNode("", "Run $(k - 1)", Any[])))
    sweep = WidgetTreeNode("", "Sweep", runs; has_children = () -> true)
    w = WidgetTree(Any[WidgetTreeNode("", "project", Any[sweep])]; expanded = Set([[1], [1, 1]]))
    io = _print_tree_rows(w)
    @test io.geometry isa WidgetModule.WTreeListGeometry
    # An open node holds a lazy list of children, so the rows declare no height,
    # and the pane walks to the ends of the list.
    @test _rows_canvas(io).elements isa ListNode && Int(_rows_canvas(io).h) == 0
    @test WidgetModule._has_no_extent_along(io.output, :y)
    # A walk down one viewport of 200 pixels reaches its ten rows of 20 pixels.
    @test _walk_tree_rows(io, 200) == 10 && made[] <= 20
    # A click on the fourth row selects the second run.
    op = _readop(io, MouseClick(:left, 100, 3 * 20 + 5, _mods; time = 0.0))
    @test op isa ReplaceSelectionOperation && WidgetModule._wtree_ref_path(op.path) == [1, 1, 2]
    # The keys step one row from the selected row.
    replace_selection!(w, _node([1, 1, 2]))
    @test WidgetModule._wtree_ref_path(_readop(io, KeyDown(:down, _mods; time = 0.0)).path) == [1, 1, 3]
    @test WidgetModule._wtree_ref_path(_readop(io, KeyDown(:up, _mods; time = 0.0)).path) == [1, 1, 1]
    # The chevron of the open node, and a click on it, need no count of its children.
    @test _has_children(w, [1, 1])
    chevron = WidgetModule._wtree_row_at(io.geometry, 20)
    toggle = _readop(io, MouseClick(:left, (chevron.chevron_x0 + chevron.chevron_x1) ÷ 2, 20 + 5, _mods;
                                    time = 0.0))
    @test toggle isa ReplaceReferencedValueOperation && !([1, 1] in toggle.value)
    @test made[] <= 20
end

@testset "a lazy list of rows finds a neighbour from the nodes, and has no row below its last" begin
    made = Ref(0)
    runs = make_index_list(10_000_000, 1, k -> (made[] += 1; WidgetTreeNode("", "Run $(k - 1)", Any[])))
    sweep = WidgetTreeNode("", "Sweep", runs; has_children = () -> true)
    # An open path deep inside the lazy list makes no walk to it.
    w = WidgetTree(Any[WidgetTreeNode("", "project", Any[sweep])];
                   expanded = Set([[1], [1, 1], [1, 1, 400_000]]))
    io = _print_tree_rows(w)
    @test io.geometry isa WidgetModule.WTreeListGeometry && made[] <= 2
    # The keys step from a row that no walk made, to the rows beside it.
    replace_selection!(w, _node([1, 1, 300]))
    @test WidgetModule._wtree_ref_path(_readop(io, KeyDown(:down, _mods; time = 0.0)).path) == [1, 1, 301]
    @test WidgetModule._wtree_ref_path(_readop(io, KeyDown(:up, _mods; time = 0.0)).path) == [1, 1, 299]
    @test made[] <= 400
    # A point below the last row of a short lazy list names no row.
    short = WidgetTree(Any[WidgetTreeNode("", "folder", make_index_list(3, 1, k -> "file $k");
                                          has_children = () -> true)];
                       expanded = Set([[1]]))
    short_io = _print_tree_rows(short)
    @test _readop(short_io, MouseClick(:left, 100, 3 * 20 + 5, _mods; time = 0.0)) isa ReplaceSelectionOperation
    @test _readop(short_io, MouseClick(:left, 100, 4 * 20 + 5, _mods; time = 0.0)) === nothing
end

# A tree in a slot, which prints its rows in a pane of its own.
_print_tree_pane(w; width = 300, height = 200) =
    print_document(_treeproj, _w2g, w,
                   ProjecturedKernel.ProjectionModule.with_exact_size(
                       PrinterContext(); width = Cell(Int32(width)), height = Cell(Int32(height))))

@testset "a far scroll moves the head of a lazy list of rows to the row at the top" begin
    made = Ref(0)
    runs = make_index_list(10_000_000, 1, k -> (made[] += 1; WidgetTreeNode("", "Run $(k - 1)", Any[])))
    sweep = WidgetTreeNode("", "Sweep", runs; has_children = () -> true)
    w = WidgetTree(Any[WidgetTreeNode("", "project", Any[sweep])]; expanded = Set([[1], [1, 1]]))
    io = _print_tree_pane(w)
    @test io isa WidgetModule.WidgetRowsPaneIoMap
    rows = io.pane.content_iomap
    head_path() = rows.geometry.head.value.row.path
    replace_selection!(w, _node([1, 1, 2]))
    # The wheel turns down, a notch at a time, until the head moves.
    turn!(notches, time) = (op = read_intent(_treeproj, io, MouseScroll(0, notches, 20, 60; time));
                            op === nothing || evaluate_operation(nothing, op))
    time = 0.0
    while w.anchor === nothing && time < 2000
        turn!(-3, time += 1.0)
    end
    @test w.anchor isa WidgetModule.WTreeListRow
    # The head is the row at the top, and the offset counts from it. Two rows lie
    # above the runs, so the head is run 199 or later.
    first_move = head_path()
    @test first_move[1:2] == [1, 1] && first_move[3] >= 199
    @test 0 <= Int(w.scroll_position.y[]) < 20
    # The rows of the new head that a walk made are few, and the selection stays.
    @test length(rows.geometry.built) <= 3
    @test WidgetModule._wtree_ref_path(w.selection) == [1, 1, 2]
    # A click at the top names the row of the head.
    time += 1.0
    click = read_intent(_treeproj, io, MouseClick(:left, 100, 5, _mods; time))
    @test click isa ReplaceSelectionOperation && WidgetModule._wtree_ref_path(click.path) == first_move
    # Down again: the head moves on, each time by about the distance.
    while head_path() == first_move && time < 4000
        turn!(-3, time += 1.0)
    end
    second_move = head_path()
    @test second_move[3] > first_move[3] + 200
    # Up past the head: the rows before it come from the links back, and the head
    # moves up.
    while head_path() == second_move && time < 6000
        turn!(3, time += 1.0)
    end
    @test head_path()[3] < second_move[3]
    @test made[] < second_move[3] + 300
end

@testset "a tree whose open nodes count their children lays out its rows and has their height" begin
    files = Any[WidgetTreeNode("", "file$(k).txt", Any[]) for k in 1:5000]
    w = WidgetTree(Any[WidgetTreeNode("", "folder", files)]; expanded = Set([[1]]))
    io = _print_tree_rows(w)
    # The folder and its 5,000 files: the renderer starts at the rows in view, and
    # the pane clamps to the rows and its bar shows them.
    @test io.geometry isa WidgetModule.WTreeGeometry && length(io.geometry.rows) == 5001
    @test Int(_rows_canvas(io).h) == 5001 * 20 && Int(io.output.h) == 5001 * 20
    @test !WidgetModule._has_no_extent_along(io.output, :y)
end

end # @testset
end # function
