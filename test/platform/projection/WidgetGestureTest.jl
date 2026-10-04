# Per-instance widget gestures: a `gestures` field on WidgetButton / WidgetTree /
# WidgetTreeNode carries `GestureBinding`s the reader consults *before* its
# built-in handling, so an instance can ADD a gesture (right-click), OVERRIDE a
# default (same pattern shadows it), or SUPPRESS one (map to `DoNothingOperation`). Empty
# tables leave a widget's behavior exactly as before. See
# plan/pending/widget-per-instance-gestures.md.


mutable struct _WidgetGestureMockEditor
    document::Any
end

function test_widget_gestures()

_always(_doc, _sel) = true

# ── WidgetButton ─────────────────────────────────────────────────────────────
_bfont = StyleFont("Ubuntu Mono", 20)
_bstub = FixedMeasure(10, 18, 6, 0)
_bproj() = ChainingProjection(
    RecursiveProjection(TypeDispatchingProjection(
        WidgetToGraphics(_bfont; measure = _bstub).dispatch)))

@testset "button: a per-instance right-click binding fires (left-click unchanged)" begin
    fired = Ref(false)
    rc = GestureBinding(MouseClickPattern(:right),
                        (doc, evt) -> InvokeActionOperation(doc.action);
                        applicable = _always, description = "context menu",
                        domain = "test")
    btn = WidgetButton("Go";
                       size = Point2D(120, 40), action = (_e) -> (fired[] = true), gestures = [rc])
    proj = _bproj()
    iomap = print_document(proj, nothing, btn, PrinterContext())
    # The built-in primary op still handles left-click.
    @test read_intent(proj, iomap, MouseClick(:left, 10, 10, ModifierKeys(); time = 0.0)) isa InvokeActionOperation
    # Right-click fires the custom binding.
    op = read_intent(proj, iomap, MouseClick(:right, 10, 10, ModifierKeys(); time = 0.0))
    @test op isa InvokeActionOperation && op.action === btn.action
    evaluate_operation(_WidgetGestureMockEditor(btn), op)
    @test fired[] == true
end

@testset "button: an instance binding shadows the default left-click" begin
    shadow = GestureBinding(MouseClickPattern(:left),
                            (doc, evt) -> ReplaceReferencedValueOperation(doc, "pressed", true);
                            applicable = _always, description = "custom left",
                            domain = "test")
    fired = Ref(false)
    btn = WidgetButton("Go";
                       size = Point2D(120, 40), action = (_e) -> (fired[] = true), gestures = [shadow])
    proj = _bproj()
    iomap = print_document(proj, nothing, btn, PrinterContext())
    op = read_intent(proj, iomap, MouseClick(:left, 10, 10, ModifierKeys(); time = 0.0))
    @test op isa ReplaceReferencedValueOperation                 # the instance binding won…
    @test !(op isa InvokeActionOperation)               # …the default primary op did not fire
end

@testset "button: suppression via DoNothingOperation makes left-click inert" begin
    fired = Ref(false)
    suppress = GestureBinding(MouseClickPattern(:left),
                              (doc, evt) -> DoNothingOperation(); applicable = _always,
                              description = "disabled left", domain = "test")
    btn = WidgetButton("Go";
                       size = Point2D(120, 40), action = (_e) -> (fired[] = true), gestures = [suppress])
    proj = _bproj()
    iomap = print_document(proj, nothing, btn, PrinterContext())
    op = read_intent(proj, iomap, MouseClick(:left, 10, 10, ModifierKeys(); time = 0.0))
    @test op isa DoNothingOperation                            # consumed, not declined
    evaluate_operation(_WidgetGestureMockEditor(btn), op)   # …and does nothing
    @test fired[] == false
end

@testset "button: a plain button with no gestures is unchanged" begin
    fired = Ref(false)
    btn = WidgetButton("Go"; size = Point2D(120, 40), action = (_e) -> (fired[] = true))
    proj = _bproj()
    iomap = print_document(proj, nothing, btn, PrinterContext())
    @test read_intent(proj, iomap, MouseClick(:left, 10, 10, ModifierKeys(); time = 0.0)) isa InvokeActionOperation
    @test read_intent(proj, iomap, MouseClick(:right, 10, 10, ModifierKeys(); time = 0.0)) === nothing
end

# ── WidgetCheckbox / WidgetSwitch (same pattern as the button) ───────────────
# The menu item carries a `gestures` field too and its reader consults it the same
# way, but it is driven through a heavier menu iomap; it is covered by the shared
# mechanism rather than a bespoke test here.

@testset "checkbox: a right-click binding fires; left-click still toggles" begin
    fired = Ref(false)
    rc = GestureBinding(MouseClickPattern(:right),
                        (doc, evt) -> (fired[] = true; DoNothingOperation());
                        applicable = _always, description = "context", domain = "test")
    cb = WidgetCheckbox(false; gestures = [rc])
    proj = _bproj()
    iomap = print_document(proj, nothing, cb, PrinterContext())
    op = read_intent(proj, iomap, MouseClick(:right, 5, 5, ModifierKeys(); time = 0.0))
    @test fired[] == true && op isa DoNothingOperation
    @test read_intent(proj, iomap, MouseClick(:left, 5, 5, ModifierKeys(); time = 0.0)) isa ReplaceReferencedValueOperation
end

@testset "switch: a right-click binding fires; left-click still toggles" begin
    fired = Ref(false)
    rc = GestureBinding(MouseClickPattern(:right),
                        (doc, evt) -> (fired[] = true; DoNothingOperation());
                        applicable = _always, description = "context", domain = "test")
    sw = WidgetSwitch(; checked = false, gestures = [rc])
    proj = _bproj()
    iomap = print_document(proj, nothing, sw, PrinterContext())
    op = read_intent(proj, iomap, MouseClick(:right, 5, 5, ModifierKeys(); time = 0.0))
    @test fired[] == true && op isa DoNothingOperation
    @test read_intent(proj, iomap, MouseClick(:left, 5, 5, ModifierKeys(); time = 0.0)) isa ReplaceReferencedValueOperation
end

# ── WidgetTree / WidgetTreeNode ──────────────────────────────────────────────
# Drive the tree projection directly (as WidgetTreeTest does), with a deterministic
# measure so row geometry is exact: row_height = 16 + 2*4 = 24, chevron column 18.
_det = FixedMeasure(8, 12, 4, 0)
_treeproj = let w2g = WidgetToGraphics(StyleFont("Ubuntu", 20); measure = _det), pr = nothing
    for (T, p) in w2g.dispatch
        T === WidgetTree && (pr = p)
    end
    pr
end
_readop(io, g) = begin
    ch = read_intent(_treeproj, nothing, Intent(g, nothing), io)
    ch isa Intent ? ch.operation : ch
end
# The path-[i] selection reference the tree reader recognises (roots[i]).
_pathref(i) = ConcreteReference(FieldReferenceStep("roots"),
                ConcreteReference(RangeReferenceStep(i - 1, i), EmptyReference()))

@testset "tree: a per-node right-click binding fires on the resolved row" begin
    opened = Ref(false)
    nb = GestureBinding(MouseClickPattern(:right),
                        (node, evt) -> (opened[] = true; DoNothingOperation());
                        applicable = _always, description = "open", domain = "test-node")
    node = WidgetTreeNode(:file, "a.jl"; gestures = [nb])
    w = WidgetTree(Any[node])
    io = print_document(_treeproj, w)
    row = io.geometry.rows[1]
    op = _readop(io, MouseClick(:right, row.chevron_x1 + 2, row.y0 + 2, ModifierKeys(); time = 0.0))
    @test opened[] == true
    @test op isa DoNothingOperation
end

@testset "tree: a node without a binding still selects on left-click" begin
    node = WidgetTreeNode(:file, "a.jl")            # no gestures
    w = WidgetTree(Any[node])
    io = print_document(_treeproj, w)
    row = io.geometry.rows[1]
    op = _readop(io, MouseClick(:left, row.chevron_x1 + 2, row.y0 + 2, ModifierKeys(); time = 0.0))
    @test op isa ReplaceSelectionOperation          # built-in select intact
end

@testset "tree: a per-node key binding fires against the selected node" begin
    entered = Ref(false)
    kb = GestureBinding(KeyDownPattern(:return),
                        (node, evt) -> (entered[] = true; DoNothingOperation());
                        applicable = _always, description = "enter", domain = "test-node")
    node = WidgetTreeNode(:file, "a.jl"; gestures = [kb])
    w = WidgetTree(Any[node])
    io = print_document(_treeproj, w)
    getfield(w, :selection)[] = _pathref(1)          # select the node
    op = _readop(io, KeyDown(:return, ModifierKeys(); time = 0.0))
    @test entered[] == true
    @test op isa DoNothingOperation
end

end # test_widget_gestures
