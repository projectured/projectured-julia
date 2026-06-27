# Actions & shortcuts (Stage 4). A shared `Action` (label, enabled, shortcut,
# callback) is referenced by a `WidgetMenuItem` (`command=`), a `WidgetButton`
# (`command=`), and a keyboard shortcut collected by `WidgetShell`. One object drives
# all three: clicking the item or the button, or pressing the shortcut, each emits
# `InvokeActionOperation(action)`; toggling `action.enabled` disables all three.

using Projectured: KeyDown

mutable struct _ActionMockEditor
    document::Any
end

function test_widget_action()
@testset "Action + shortcuts" begin

proj = make_widget_projection_example()

@testset "one Action drives a menu item, a toolbar button, and a shortcut" begin
    fired = Ref(0)
    save = Action("Save"; shortcut = Shortcut(:s; ctrl = true), callback = (_e) -> (fired[] += 1))

    # Menu item bound to the command.
    item = WidgetMenuItem("Save"; command = save)
    iio  = projection_print(proj, item)
    iop  = projection_read(proj, iio, MousePress(:left, 2, 2, Modifiers()))
    @test iop isa CompoundOperation
    @test iop.operations[1] isa InvokeActionOperation
    @test iop.operations[1].action === save

    # Button bound to the same command.
    btn = WidgetButton(Point2D(0, 0), Point2D(80, 0), "Save"; command = save)
    bio = projection_print(proj, btn)
    bop = projection_read(proj, bio, MousePress(:left, 2, 2, Modifiers()))
    @test bop isa InvokeActionOperation
    @test bop.action === save

    # Keyboard shortcut collected by the shell from its menu bar.
    shell = WidgetShell(WidgetLabel(Point2D(0, 0), "body");
                        menu_bar = WidgetMenu([WidgetMenuItem("Save"; command = save)]),
                        size = Point2D(300, 200))
    sio = projection_print(proj, shell)
    sop = projection_read(proj, sio, KeyDown(:s, Modifiers(ctrl = true), false))
    @test sop isa InvokeActionOperation
    @test sop.action === save

    # All three route to the same callback.
    evaluate_operation(_ActionMockEditor(save), iop.operations[1])
    evaluate_operation(_ActionMockEditor(save), bop)
    evaluate_operation(_ActionMockEditor(save), sop)
    @test fired[] == 3
end

@testset "toggling the Action's enabled disables all three" begin
    save = Action("Save"; enabled = false,
                  shortcut = Shortcut(:s; ctrl = true), callback = (_e) -> error("must not fire"))

    item = WidgetMenuItem("Save"; command = save)
    iio  = projection_print(proj, item)
    @test projection_read(proj, iio, MousePress(:left, 2, 2, Modifiers())) === nothing

    btn = WidgetButton(Point2D(0, 0), Point2D(80, 0), "Save"; command = save)
    bio = projection_print(proj, btn)
    @test projection_read(proj, bio, MousePress(:left, 2, 2, Modifiers())) === nothing

    shell = WidgetShell(WidgetLabel(Point2D(0, 0), "body");
                        menu_bar = WidgetMenu([WidgetMenuItem("Save"; command = save)]),
                        size = Point2D(300, 200))
    sio = projection_print(proj, shell)
    # The disabled action's shortcut does not fire; the key falls through instead.
    sop = projection_read(proj, sio, KeyDown(:s, Modifiers(ctrl = true), false))
    @test !(sop isa InvokeActionOperation)

    # Re-enabling makes the shortcut fire again (reactive `enabled` cell).
    save.enabled = true
    sop2 = projection_read(proj, sio, KeyDown(:s, Modifiers(ctrl = true), false))
    @test sop2 isa InvokeActionOperation
end

@testset "a shortcut is consumed by the shell, ahead of the focused child" begin
    fired = Ref(0)
    save  = Action("Save"; shortcut = Shortcut(:s; ctrl = true), callback = (_e) -> (fired[] += 1))
    shell = WidgetShell(WidgetLabel(Point2D(0, 0), "body");
                        menu_bar = WidgetMenu([WidgetMenuItem("Save"; command = save)]),
                        size = Point2D(300, 200))
    sio = projection_print(proj, shell)

    # The matching chord is consumed (returns the action op).
    @test projection_read(proj, sio, KeyDown(:s, Modifiers(ctrl = true), false)) isa InvokeActionOperation
    # A non-matching chord is not claimed as a shortcut (it falls through).
    @test !(projection_read(proj, sio, KeyDown(:x, Modifiers(ctrl = true), false)) isa InvokeActionOperation)
    # Exact-modifier matching: bare `s` (no Ctrl) is not the Ctrl+S shortcut.
    @test !(projection_read(proj, sio, KeyDown(:s, Modifiers(), false)) isa InvokeActionOperation)
end

@testset "InvokeActionOperation respects enabled at evaluate time" begin
    fired = Ref(0)
    a = Action("X"; enabled = false, callback = (_e) -> (fired[] += 1))
    evaluate_operation(_ActionMockEditor(a), InvokeActionOperation(a))
    @test fired[] == 0
    a.enabled = true
    evaluate_operation(_ActionMockEditor(a), InvokeActionOperation(a))
    @test fired[] == 1
end

@testset "WidgetStatusBar renders its segments as a bottom band" begin
    sb = WidgetStatusBar(["Ready", "Ln 1, Col 1"])
    iomap = projection_print(proj, sb)
    @test iomap.output isa GraphicsCanvas
    @test Int(iomap.output.w[]) > 0
    # Both segments are drawn as text (helper defined in WidgetDialogTest).
    @test _dialog_text_xy(iomap.output, "Ready") !== nothing
    @test _dialog_text_xy(iomap.output, "Ln 1, Col 1") !== nothing
    # A status bar is inert.
    @test projection_read(proj, iomap, MousePress(:left, 2, 2, Modifiers())) === nothing
end

end # @testset
end # function
