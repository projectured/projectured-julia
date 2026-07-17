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
_bfont = font_ubuntu_monospace_regular_20
_bstub(t, f) = (length(t) * 10, 24)
_bproj() = ChainingProjection(
    WidgetHoverTrackingProjection(inner = RecursiveProjection(TypeDispatchingProjection(
        WidgetToGraphics(_bfont; measure = _bstub).dispatch))))

@testset "button: a per-instance right-click binding fires (left-click unchanged)" begin
    fired = Ref(false)
    rc = GestureBinding(MousePressPattern(:right, nothing, nothing),
                        (doc, evt) -> InvokeWidgetActionOperation(doc),
                        _always, "context menu", "test")
    btn = WidgetButton(Point2D(0, 0), Point2D(120, 40), "Go";
                       action = (_e) -> (fired[] = true), gestures = [rc])
    proj = _bproj()
    iomap = print_document(proj, nothing, btn, PrinterContext())
    # The built-in primary op still handles left-click.
    @test read_intent(proj, iomap, MousePress(:left, 10, 10, ModifierKeys())) isa InvokeWidgetActionOperation
    # Right-click fires the custom binding.
    op = read_intent(proj, iomap, MousePress(:right, 10, 10, ModifierKeys()))
    @test op isa InvokeWidgetActionOperation && op.widget === btn
    evaluate_operation(_WidgetGestureMockEditor(btn), op)
    @test fired[] == true
end

@testset "button: an instance binding shadows the default left-click" begin
    shadow = GestureBinding(MousePressPattern(:left, nothing, nothing),
                            (doc, evt) -> ReplaceReferencedValueOperation(doc, "hovered", true),
                            _always, "custom left", "test")
    fired = Ref(false)
    btn = WidgetButton(Point2D(0, 0), Point2D(120, 40), "Go";
                       action = (_e) -> (fired[] = true), gestures = [shadow])
    proj = _bproj()
    iomap = print_document(proj, nothing, btn, PrinterContext())
    op = read_intent(proj, iomap, MousePress(:left, 10, 10, ModifierKeys()))
    @test op isa ReplaceReferencedValueOperation                 # the instance binding won…
    @test !(op isa InvokeWidgetActionOperation)         # …the default primary op did not fire
end

@testset "button: suppression via DoNothingOperation makes left-click inert" begin
    fired = Ref(false)
    suppress = GestureBinding(MousePressPattern(:left, nothing, nothing),
                              (doc, evt) -> DoNothingOperation(),
                              _always, "disabled left", "test")
    btn = WidgetButton(Point2D(0, 0), Point2D(120, 40), "Go";
                       action = (_e) -> (fired[] = true), gestures = [suppress])
    proj = _bproj()
    iomap = print_document(proj, nothing, btn, PrinterContext())
    op = read_intent(proj, iomap, MousePress(:left, 10, 10, ModifierKeys()))
    @test op isa DoNothingOperation                            # consumed, not declined
    evaluate_operation(_WidgetGestureMockEditor(btn), op)   # …and does nothing
    @test fired[] == false
end

@testset "button: a plain button with no gestures is unchanged" begin
    fired = Ref(false)
    btn = WidgetButton(Point2D(0, 0), Point2D(120, 40), "Go"; action = (_e) -> (fired[] = true))
    proj = _bproj()
    iomap = print_document(proj, nothing, btn, PrinterContext())
    @test read_intent(proj, iomap, MousePress(:left, 10, 10, ModifierKeys())) isa InvokeWidgetActionOperation
    @test read_intent(proj, iomap, MousePress(:right, 10, 10, ModifierKeys())) === nothing
end

# ── WidgetCheckbox / WidgetSwitch (same pattern as the button) ───────────────
# The menu item carries a `gestures` field too and its reader consults it the same
# way, but it is driven through a heavier menu iomap; it is covered by the shared
# mechanism rather than a bespoke test here.

@testset "checkbox: a right-click binding fires; left-click still toggles" begin
    fired = Ref(false)
    rc = GestureBinding(MousePressPattern(:right, nothing, nothing),
                        (doc, evt) -> (fired[] = true; DoNothingOperation()),
                        _always, "context", "test")
    cb = WidgetCheckbox(Point2D(0, 0), false; gestures = [rc])
    proj = _bproj()
    iomap = print_document(proj, nothing, cb, PrinterContext())
    op = read_intent(proj, iomap, MousePress(:right, 5, 5, ModifierKeys()))
    @test fired[] == true && op isa DoNothingOperation
    @test read_intent(proj, iomap, MousePress(:left, 5, 5, ModifierKeys())) isa ReplaceReferencedValueOperation
end

@testset "switch: a right-click binding fires; left-click still toggles" begin
    fired = Ref(false)
    rc = GestureBinding(MousePressPattern(:right, nothing, nothing),
                        (doc, evt) -> (fired[] = true; DoNothingOperation()),
                        _always, "context", "test")
    sw = WidgetSwitch(Point2D(0, 0), false; gestures = [rc])
    proj = _bproj()
    iomap = print_document(proj, nothing, sw, PrinterContext())
    op = read_intent(proj, iomap, MousePress(:right, 5, 5, ModifierKeys()))
    @test fired[] == true && op isa DoNothingOperation
    @test read_intent(proj, iomap, MousePress(:left, 5, 5, ModifierKeys())) isa ReplaceReferencedValueOperation
end

# ── WidgetTree / WidgetTreeNode ──────────────────────────────────────────────
# Drive the tree projection directly (as WidgetTreeTest does), with a deterministic
# measure so row geometry is exact: row_height = 16 + 2*4 = 24, chevron column 18.
_det = (t, f) -> (length(t) * 8, 16)
_treeproj = let w2g = WidgetToGraphics(font_ubuntu_regular_20; measure = _det), pr = nothing
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
_pathref(i) = ConcreteReferencePath(FieldReference("roots"),
                ConcreteReferencePath(RangeReference(i - 1, i), EmptyReferencePath()))

@testset "tree: a per-node right-click binding fires on the resolved row" begin
    opened = Ref(false)
    nb = GestureBinding(MousePressPattern(:right, nothing, nothing),
                        (node, evt) -> (opened[] = true; DoNothingOperation()),
                        _always, "open", "test-node")
    node = WidgetTreeNode(:file, "a.jl"; gestures = [nb])
    w = WidgetTree(Point2D(0, 0), Any[node])
    io = print_document(_treeproj, w)
    row = io.geometry[].rows[1]
    op = _readop(io, MousePress(:right, row.chevron_x1 + 2, row.y0 + 2, ModifierKeys()))
    @test opened[] == true
    @test op isa DoNothingOperation
end

@testset "tree: a node without a binding still selects on left-click" begin
    node = WidgetTreeNode(:file, "a.jl")            # no gestures
    w = WidgetTree(Point2D(0, 0), Any[node])
    io = print_document(_treeproj, w)
    row = io.geometry[].rows[1]
    op = _readop(io, MousePress(:left, row.chevron_x1 + 2, row.y0 + 2, ModifierKeys()))
    @test op isa ReplaceSelectionOperation          # built-in select intact
end

@testset "tree: a per-node key binding fires against the selected node" begin
    entered = Ref(false)
    kb = GestureBinding(KeyDownPattern(:return, nothing, nothing),
                        (node, evt) -> (entered[] = true; DoNothingOperation()),
                        _always, "enter", "test-node")
    node = WidgetTreeNode(:file, "a.jl"; gestures = [kb])
    w = WidgetTree(Point2D(0, 0), Any[node])
    io = print_document(_treeproj, w)
    getfield(w, :selection)[] = _pathref(1)          # select the node
    op = _readop(io, KeyDown(:return, ModifierKeys()))
    @test entered[] == true
    @test op isa DoNothingOperation
end

end # test_widget_gestures
