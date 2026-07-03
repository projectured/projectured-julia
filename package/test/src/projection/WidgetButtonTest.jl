mutable struct _WidgetButtonMockEditor
    document::Any
end

function test_widget_button_behavior()

_font = font_ubuntu_monospace_regular_20
_stub(t, f) = (length(t) * 10, 24)

# Recursively scan a canvas's elements for a GraphicsImage (canvases nest other
# canvases as elements).
function _canvas_has_image(canvas)
    for elem in canvas.elements
        elem isa GraphicsImage && return true
        elem isa GraphicsCanvas && _canvas_has_image(elem) && return true
    end
    false
end

# The standard widget renderer used by the button examples.
_proj() = ChainingProjection(
    WidgetHoverTrackingProjection(inner = RecursiveProjection(TypeDispatchingProjection(
        WidgetToGraphics(_font; measure=_stub).dispatch))))

# A lone button with a side-effecting action over a captured counter.
function _button_doc()
    count = Ref(0)
    button = WidgetButton(Point2D(0, 0), Point2D(120, 40), "Go";
                          action = (_editor) -> (count[] += 1))
    (button, count)
end

@testset "button click invokes its action via InvokeWidgetActionOperation" begin
    button, count = _button_doc()
    proj = _proj()
    iomap = projection_print(proj, nothing, button, PrinterContext())
    @test iomap.output isa GraphicsCanvas

    # Click inside the button (its canvas is at 0,0 sized 120×40).
    op = projection_read(proj, iomap, MousePress(:left, 10, 10, Modifiers()))
    @test op isa InvokeWidgetActionOperation
    @test op.widget === button

    evaluate_operation(_WidgetButtonMockEditor(button), op)
    @test count[] == 1
    evaluate_operation(_WidgetButtonMockEditor(button), op)
    @test count[] == 2
end

@testset "a non-left click does nothing" begin
    button, _ = _button_doc()
    proj = _proj()
    iomap = projection_print(proj, nothing, button, PrinterContext())
    @test projection_read(proj, iomap, MousePress(:right, 10, 10, Modifiers())) === nothing
end

@testset "press / release drive the transient pressed flag" begin
    button, _ = _button_doc()
    proj = _proj()
    iomap = projection_print(proj, nothing, button, PrinterContext())

    down = projection_read(proj, iomap, MouseDown(:left, 10, 10, Modifiers()))
    @test down isa ReplaceReferencedValueOperation
    @test down.value == true
    evaluate_operation(_WidgetButtonMockEditor(button), down)
    @test button.pressed == true

    up = projection_read(proj, iomap, MouseUp(:left, 10, 10, Modifiers()))
    @test up isa ReplaceReferencedValueOperation
    @test up.value == false
    evaluate_operation(_WidgetButtonMockEditor(button), up)
    @test button.pressed == false
end

@testset "a move over the button sets its hovered flag" begin
    button, _ = _button_doc()
    proj = _proj()
    iomap = projection_print(proj, nothing, button, PrinterContext())
    op = projection_read(proj, iomap, MouseMove(10, 10, :none, Modifiers()))
    @test op isa ReplaceReferencedValueOperation
    @test op.document === button && op.value == true
    evaluate_operation(_WidgetButtonMockEditor(button), op)
    @test button.hovered == true
end

@testset "the hover tracker clears the previously-hovered button on leave" begin
    # Two buttons side by side inside a composite.
    a = WidgetButton(Point2D(0, 0), Point2D(100, 40), "A"; action = (_e) -> nothing)
    b = WidgetButton(Point2D(120, 0), Point2D(100, 40), "B"; action = (_e) -> nothing)
    composite = WidgetComposite(Point2D(0, 0), Any[a, b])
    proj = _proj()                          # one tracker instance, reused across reads
    ed = _WidgetButtonMockEditor(composite)

    iomap = projection_print(proj, nothing, composite, PrinterContext())
    op_a = projection_read(proj, iomap, MouseMove(10, 10, :none, Modifiers()))
    @test op_a isa ReplaceReferencedValueOperation && op_a.document === a
    evaluate_operation(ed, op_a)
    @test a.hovered == true

    # Move onto B: the tracker clears A (hover + press) and sets B.
    iomap2 = projection_print(proj, nothing, composite, PrinterContext())
    op_b = projection_read(proj, iomap2, MouseMove(130, 10, :none, Modifiers()))
    @test op_b isa CompoundOperation
    evaluate_operation(ed, op_b)
    @test a.hovered == false
    @test b.hovered == true

    # Move into dead space: B clears, nothing new hovered.
    iomap3 = projection_print(proj, nothing, composite, PrinterContext())
    op_void = projection_read(proj, iomap3, MouseMove(300, 300, :none, Modifiers()))
    evaluate_operation(ed, op_void)
    @test b.hovered == false
end

@testset "button click inside a composite still reaches the action" begin
    count = Ref(0)
    button = WidgetButton(Point2D(0, 0), Point2D(100, 40), "X";
                          action = (_e) -> (count[] += 1))
    composite = WidgetComposite(Point2D(0, 0), Any[button])
    proj = _proj()
    iomap = projection_print(proj, nothing, composite, PrinterContext())
    op = projection_read(proj, iomap, MousePress(:left, 10, 10, Modifiers()))
    @test op isa InvokeWidgetActionOperation && op.widget === button
    evaluate_operation(_WidgetButtonMockEditor(composite), op)
    @test count[] == 1
end

@testset "an ImageDocument content renders as a GraphicsImage" begin
    # A 2×2 RGBA buffer carried by an ImageMemory, so no decode/SDL is needed.
    pixels = UInt8[0xff,0x00,0x00,0xff, 0x00,0xff,0x00,0xff,
                   0x00,0x00,0xff,0xff, 0xff,0xff,0xff,0xff]
    image = ImageMemory((pixels, 2, 2))
    button = WidgetButton(Point2D(0, 0), Point2D(40, 40), image; action = (_e) -> nothing)
    iomap = projection_print(_proj(), nothing, button, PrinterContext())
    canvas = iomap.output
    @test canvas isa GraphicsCanvas
    @test _canvas_has_image(canvas)
end

@testset "a label with image content renders a GraphicsImage at its natural size" begin
    pixels = UInt8[0xff,0x00,0x00,0xff, 0x00,0xff,0x00,0xff,
                   0x00,0x00,0xff,0xff, 0xff,0xff,0xff,0xff]
    label = WidgetLabel(Point2D(0, 0), ImageMemory((pixels, 2, 2)))
    iomap = projection_print(_proj(), nothing, label, PrinterContext())
    @test _canvas_has_image(iomap.output)
end

# Stage 1, Step 1: the shared `enabled` interactivity flag. Defaults to `true`,
# is settable by keyword, and — because it is threaded through the order-sensitive
# positional constructor right after `visible` — must not shift any other field.
@testset "enabled flag: defaults true, settable, and leaves other fields intact" begin
    btn = WidgetButton(Point2D(0, 0), Point2D(120, 40), "Go")
    @test btn.enabled === true
    @test btn.visible === true                       # slot after visible not shifted
    btn_off = WidgetButton(Point2D(0, 0), Point2D(120, 40), "Go"; enabled=false)
    @test btn_off.enabled === false
    @test btn_off.visible === true
    # A disabled button is still a normal document: it prints to a canvas.
    @test projection_print(_proj(), nothing, btn_off, PrinterContext()).output isa GraphicsCanvas

    cb = WidgetCheckbox(Point2D(0, 0), true)
    @test cb.enabled === true
    @test cb.content === true                         # content slot intact
    cb_off = WidgetCheckbox(Point2D(0, 0), false; enabled=false)
    @test cb_off.enabled === false
    @test cb_off.content === false
end

# Stage 1, Step 2: a disabled control still prints, but its reader emits no
# operation for any pointer event — no action, no toggle, no hover/press state.
@testset "a disabled button is inert: no action, no hover/press" begin
    fired = Ref(false)
    btn = WidgetButton(Point2D(0, 0), Point2D(120, 40), "Go";
                       action = (_e) -> (fired[] = true), enabled = false)
    proj = _proj()
    iomap = projection_print(proj, nothing, btn, PrinterContext())
    @test iomap.output isa GraphicsCanvas                      # disabled still renders
    @test projection_read(proj, iomap, MousePress(:left, 10, 10, Modifiers())) === nothing
    @test projection_read(proj, iomap, MouseDown(:left, 10, 10, Modifiers())) === nothing
    @test projection_read(proj, iomap, MouseMove(10, 10, :none, Modifiers())) === nothing
    @test fired[] == false
    @test btn.hovered == false && btn.pressed == false
end

@testset "a disabled checkbox swallows the toggle click" begin
    cb = WidgetCheckbox(Point2D(0, 0), false; enabled = false)
    proj = _proj()
    iomap = projection_print(proj, nothing, cb, PrinterContext())
    @test iomap.output isa GraphicsCanvas
    @test projection_read(proj, iomap, MousePress(:left, 5, 5, Modifiers())) === nothing
    @test cb.content === false                                # value unchanged
end

# Stage 1, Step 5: the `enabled` field is carried uniformly across the other
# interactive controls — default true, settable by keyword, and threaded through
# each order-sensitive positional constructor without shifting a neighbour field.
@testset "enabled flag is present on the other interactive widgets" begin
    @test WidgetText(Point2D(0, 0), "x").enabled === true
    @test WidgetText(Point2D(0, 0), "x"; enabled=false).enabled === false
    @test WidgetTextarea(Point2D(0, 0), "x").enabled === true
    @test WidgetTextarea(Point2D(0, 0), "x"; rows=3, enabled=false).enabled === false
    @test WidgetTextarea(Point2D(0, 0), "x"; rows=3).rows == 3          # neighbour intact
    @test WidgetSelect(Point2D(0, 0), "v").enabled === true
    @test WidgetSelect(Point2D(0, 0), "v"; enabled=false).enabled === false
    @test WidgetSwitch(Point2D(0, 0), true).enabled === true
    @test WidgetSwitch(Point2D(0, 0), true; enabled=false).checked === true   # neighbour intact
    @test WidgetSlider(Point2D(0, 0), 0.3).enabled === true
    @test WidgetSlider(Point2D(0, 0), 0.3; enabled=false).value == 0.3        # neighbour intact
    @test WidgetToggle(Point2D(0, 0), "t"; pressed=true).enabled === true
    @test WidgetToggle(Point2D(0, 0), "t"; pressed=true, enabled=false).pressed === true
    @test WidgetToggleGroup(Point2D(0, 0), ["a","b"]; selected=2).enabled === true
    @test WidgetToggleGroup(Point2D(0, 0), ["a","b"]; selected=2).selected == 2
    @test WidgetRadioGroup(Point2D(0, 0), ["a","b"]; selected=2).enabled === true
    @test WidgetRadioGroup(Point2D(0, 0), ["a","b"]; selected=2, enabled=false).selected == 2
    @test WidgetMenuItem("m").enabled === true
    @test WidgetMenuItem("m"; enabled=false).enabled === false
end

# Stage 1, Step 3: the disabled surface differs from the enabled one (muted fill
# / no drop shadow). We compare the element count: an enabled resting button
# carries an extra shadow rect that the disabled one drops.
@testset "a disabled button renders flat (no shadow rect)" begin
    on  = WidgetButton(Point2D(0, 0), Point2D(120, 40), "Go")
    off = WidgetButton(Point2D(0, 0), Point2D(120, 40), "Go"; enabled = false)
    proj = _proj()
    on_canvas  = projection_print(proj, nothing, on,  PrinterContext()).output
    off_canvas = projection_print(proj, nothing, off, PrinterContext()).output
    @test length(off_canvas.elements) < length(on_canvas.elements)
end

# Stage 1, Step 6: the reader-less controls (Switch / Toggle / Select) gained a
# muted disabled appearance. They have no reader to gate, so we just exercise the
# disabled print branch (it must not error and must still produce a canvas).
@testset "disabled Switch / Toggle / Select still render via the muted branch" begin
    proj = _proj()
    for w in (WidgetSwitch(Point2D(0, 0), true; enabled=false),
              WidgetToggle(Point2D(0, 0), "Bold"; pressed=true, enabled=false),
              WidgetSelect(Point2D(0, 0), "Apple"; width=180, enabled=false))
        @test projection_print(proj, nothing, w, PrinterContext()).output isa GraphicsCanvas
    end
end

# Stage 2, Step 5: the focus ring renders on the selected widget (focus = a
# non-nothing selection), adding exactly one ring element to the canvas.
@testset "focus ring renders on the selected widget" begin
    proj = _proj()
    # The focus ring is a *persistent* overlay element (present whether or not the
    # widget is focused) so a pure selection move never rebuilds the elements vector
    # — printer-locality dimension A. Focus drives its w/h from 0 (hidden; the
    # renderer skips a zero-size rect) to the full control bounds. The ring is the
    # transparent-fill (color.alpha=0) bordered (border_width>0) rect. Distinct instances per
    # case, since each ring's lazy w/h reads its own widget's live selection.
    _ring(canvas) = let els = [e isa Cell ? e[] : e for e in collect(canvas.elements)]
        i = findfirst(e -> e isa GraphicsRect && e.color.alpha == 0 && Int(e.border_width) > 0, els)
        i === nothing ? nothing : els[i]
    end
    for mk in (() -> WidgetButton(Point2D(0, 0), Point2D(80, 30), "Go"),
               () -> WidgetCheckbox(Point2D(0, 0), false))
        un = projection_print(proj, nothing, mk(), PrinterContext()).output
        fw = mk(); getfield(fw, :selection)[] = EmptyReferencePath()
        fo = projection_print(proj, nothing, fw, PrinterContext()).output
        # Same element count in both states (the ring element is persistent)…
        @test length(collect(fo.elements)) == length(collect(un.elements))
        ru = _ring(un); rf = _ring(fo)
        @test ru !== nothing && rf !== nothing
        # …and the ring is collapsed to 0×0 when unfocused, full bounds when focused.
        @test Int(ru.w) == 0 && Int(ru.h) == 0
        @test Int(rf.w) > 0 && Int(rf.h) > 0
    end
end

# Stage 2, Step 4: Enter/Space activate the focused button/checkbox (the keystroke
# reaches the focused leaf via selection routing). Disabled leaves stay inert.
@testset "Enter/Space activate the focused button and checkbox" begin
    proj = _proj()
    btn = WidgetButton(Point2D(0, 0), Point2D(80, 30), "Go"; action = (_e) -> nothing)
    biomap = projection_print(proj, nothing, btn, PrinterContext())
    @test projection_read(proj, biomap, KeyDown(:return, Modifiers())) isa InvokeWidgetActionOperation
    @test projection_read(proj, biomap, KeyDown(:space,  Modifiers())) isa InvokeWidgetActionOperation
    dbtn = WidgetButton(Point2D(0, 0), Point2D(80, 30), "Go"; action = (_e) -> nothing, enabled = false)
    @test projection_read(proj, projection_print(proj, nothing, dbtn, PrinterContext()),
                          KeyDown(:return, Modifiers())) === nothing

    cb = WidgetCheckbox(Point2D(0, 0), false)
    ciomap = projection_print(proj, nothing, cb, PrinterContext())
    op = projection_read(proj, ciomap, KeyDown(:space, Modifiers()))
    @test op isa ReplaceReferencedValueOperation && op.value == true
    @test projection_read(proj, ciomap, KeyDown(:return, Modifiers())) isa ReplaceReferencedValueOperation
    dcb = WidgetCheckbox(Point2D(0, 0), false; enabled = false)
    @test projection_read(proj, projection_print(proj, nothing, dcb, PrinterContext()),
                          KeyDown(:space, Modifiers())) === nothing
end

# Stage 2, Step 2: first/last_focusable_path locate enabled interactive leaves as
# relative ∅ paths, skipping disabled ones, and recurse through containers.
@testset "first/last_focusable_path find enabled leaves and skip disabled" begin
    # A bare focusable leaf is its own whole-element (∅) selection.
    @test first_focusable_path(WidgetButton(Point2D(0,0), Point2D(80,30), "A")) isa EmptyReferencePath
    # A disabled leaf has no focusable path.
    @test first_focusable_path(WidgetButton(Point2D(0,0), Point2D(80,30), "A"; enabled=false)) === nothing
    # A display-only widget has none either.
    @test first_focusable_path(WidgetLabel(Point2D(0,0), "x")) === nothing

    comp = WidgetComposite(Point2D(0,0), Any[
        WidgetButton(Point2D(0,0), Point2D(80,30), "A"),
        WidgetButton(Point2D(0,0), Point2D(80,30), "B"; enabled=false),
        WidgetCheckbox(Point2D(0,0), true),
    ])
    fp = first_focusable_path(comp)
    @test fp isa ConcreteReferencePath
    @test fp.head isa FieldReference && fp.head.name == "elements"
    @test fp.tail.head isa RangeReference && fp.tail.head.start == 0      # slot 1 (enabled button)
    @test fp.tail.tail isa EmptyReferencePath
    lp = last_focusable_path(comp)
    @test lp.tail.head.start == 2                                         # slot 3 (checkbox); disabled slot 2 skipped

    # Nested: the first focusable descends into the child container.
    nested = WidgetComposite(Point2D(0,0), Any[
        WidgetLabel(Point2D(0,0), "x"),                                   # skipped (not focusable)
        WidgetComposite(Point2D(0,0), Any[WidgetCheckbox(Point2D(0,0), false)]),
    ])
    np = first_focusable_path(nested)
    @test np.head.name == "elements" && np.tail.head.start == 1          # outer slot 2
    @test np.tail.tail.head isa FieldReference && np.tail.tail.head.name == "elements"
    @test np.tail.tail.tail.head.start == 0                               # inner slot 1
end

# Regression: an embedded `ListNode` (the doubly-linked backing of text/syntax/
# collection lists) is cyclic — `prev`/`next` point at each other — so the focus
# walk recursed `next → prev → next …` forever and Tab stack-overflowed on the
# workbench/assistant examples. The objectid `visited` guard must make it terminate.
@testset "focus traversal terminates on a cyclic ListNode graph" begin
    a = ListNode("x"); b = ListNode("y")
    a.next = b; b.prev = a                                  # a ⇄ b (the prev/next cycle)
    @test first_focusable_path(a) === nothing               # no focusable; terminates (was StackOverflow)
    @test last_focusable_path(a)  === nothing
    # A focusable widget stored as a node's value is still reached (the walk doesn't loop).
    c = ListNode(WidgetButton(Point2D(0,0), Point2D(40,20), "OK")); d = ListNode("z")
    c.next = d; d.prev = c
    @test first_focusable_path(c) isa ConcreteReferencePath
end

# Stage 2, Step 3: distributed Tab traversal in the composite reader. Tab moves
# the selection to the next focusable child (skipping disabled ones); bootstrap
# focuses the first; the last child declines (no wrap yet). Shift-Tab reverses.
@testset "composite Tab advances the selection across focusable children" begin
    _mk(i) = ConcreteReferencePath(FieldReference("elements"),
                ConcreteReferencePath(RangeReference(i - 1, i), EmptyReferencePath()))
    _btn(t) = WidgetButton(Point2D(0, 0), Point2D(80, 30), t)
    _slot(op) = op.path.tail.head.start + 1          # 1-based selected slot from the op
    proj = _proj()
    tab  = KeyDown(:tab, Modifiers())
    stab = KeyDown(:tab, Modifiers(shift=true))
    _read(c, ev) = projection_read(proj, projection_print(proj, nothing, c, PrinterContext()), ev)

    comp = WidgetComposite(Point2D(0, 0), Any[_btn("A"), WidgetCheckbox(Point2D(0, 0), true), _btn("C")])

    # Bootstrap: nothing selected (∅ on the composite) → first focusable (slot 1).
    op = _read(comp, tab)
    @test op isa ReplaceSelectionOperation && _slot(op) == 1

    getfield(comp, :selection)[] = _mk(1)
    @test _slot(_read(comp, tab)) == 2               # slot 1 → 2

    getfield(comp, :selection)[] = _mk(2)
    @test _slot(_read(comp, tab)) == 3               # slot 2 → 3

    getfield(comp, :selection)[] = _mk(3)
    @test _slot(_read(comp, tab)) == 1               # last wraps to first (top-level rule)

    getfield(comp, :selection)[] = _mk(2)
    @test _slot(_read(comp, stab)) == 1              # Shift-Tab: slot 2 → 1

    getfield(comp, :selection)[] = _mk(1)
    @test _slot(_read(comp, stab)) == 3              # Shift-Tab on first wraps to last

    # Disabled children are not Tab stops.
    comp2 = WidgetComposite(Point2D(0, 0), Any[_btn("A"),
              WidgetButton(Point2D(0, 0), Point2D(80, 30), "B"; enabled=false), _btn("C")])
    getfield(comp2, :selection)[] = _mk(1)
    @test _slot(_read(comp2, tab)) == 3              # slot 2 skipped
end

# Stage 2, Step 3: the same distributed Tab in the LayoutDocument readers. Layout
# children sit under `children[i]` (vs the composite's `elements[i]`), so this
# exercises the layout-specific path shape and the cross-module focus helpers.
@testset "layout Tab advances the selection across focusable children" begin
    _mk(i) = ConcreteReferencePath(FieldReference("children"),
                ConcreteReferencePath(RangeReference(i - 1, i), EmptyReferencePath()))
    _btn(t) = WidgetButton(Point2D(0, 0), Point2D(80, 30), t)
    _slot(op) = op.path.tail.head.start + 1
    # A renderer that dispatches both layout nodes and widget nodes (as the widget
    # examples do), wrapped in the hover tracker for the top-level Tab wrap-around.
    lproj = ChainingProjection(WidgetHoverTrackingProjection(inner =
        RecursiveProjection(TypeDispatchingProjection(vcat(
            LayoutToGraphics().dispatch,
            WidgetToGraphics(_font; measure=_stub).dispatch)))))
    tab = KeyDown(:tab, Modifiers())
    _read(c, ev) = projection_read(lproj, projection_print(lproj, nothing, c, PrinterContext()), ev)

    lay = VerticalLayout(Any[_btn("A"), WidgetCheckbox(Point2D(0, 0), true), _btn("C")]; gap=8)
    op = _read(lay, tab)                              # bootstrap → first focusable
    @test op isa ReplaceSelectionOperation && op.path.head isa FieldReference
    @test op.path.head.name == "children" && _slot(op) == 1
    getfield(lay, :selection)[] = _mk(1)
    @test _slot(_read(lay, tab)) == 2                # slot 1 → 2
    getfield(lay, :selection)[] = _mk(3)
    @test _slot(_read(lay, tab)) == 1               # last wraps to first
end

end # test_widget_button_behavior
