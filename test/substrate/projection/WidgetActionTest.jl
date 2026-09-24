# Actions & shortcuts (Stage 4). One shared `Action` (label, icon, enabled,
# shortcut, callback) is bound by a `WidgetMenuItem`, a `WidgetButton`, and a
# keyboard shortcut collected by `WidgetShell` — each control is a VIEW of it.
# Clicking the item or the button, or pressing the shortcut, each emits
# `InvokeActionOperation(action)`; toggling `action.enabled` disables all three.


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
    item = WidgetMenuItem(save)
    iio  = print_document(proj, item)
    iop  = read_intent(proj, iio, MousePress(:left, 2, 2, ModifierKeys()))
    @test iop isa CompoundOperation
    @test iop.operations[1] isa InvokeActionOperation
    @test iop.operations[1].action === save

    # Button bound to the same command.
    btn = WidgetButton(save; size = Point2D(80, 0))
    bio = print_document(proj, btn)
    bop = read_intent(proj, bio, MousePress(:left, 2, 2, ModifierKeys()))
    @test bop isa InvokeActionOperation
    @test bop.action === save

    # Keyboard shortcut collected by the shell from its menu bar.
    shell = WidgetShell(WidgetLabel("body");
                        menu_bar = WidgetMenu([WidgetMenuItem(save)]),
                        size = Point2D(300, 200))
    sio = print_document(proj, shell)
    sop = read_intent(proj, sio, KeyDown(:s, ModifierKeys(ctrl = true), false))
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

    item = WidgetMenuItem(save)
    iio  = print_document(proj, item)
    @test read_intent(proj, iio, MousePress(:left, 2, 2, ModifierKeys())) === nothing

    btn = WidgetButton(save; size = Point2D(80, 0))
    bio = print_document(proj, btn)
    @test read_intent(proj, bio, MousePress(:left, 2, 2, ModifierKeys())) === nothing

    shell = WidgetShell(WidgetLabel("body");
                        menu_bar = WidgetMenu([WidgetMenuItem(save)]),
                        size = Point2D(300, 200))
    sio = print_document(proj, shell)
    # The disabled action's shortcut does not fire; the key falls through instead.
    sop = read_intent(proj, sio, KeyDown(:s, ModifierKeys(ctrl = true), false))
    @test !(sop isa InvokeActionOperation)

    # Re-enabling makes the shortcut fire again (reactive `enabled` cell).
    save.enabled = true
    sop2 = read_intent(proj, sio, KeyDown(:s, ModifierKeys(ctrl = true), false))
    @test sop2 isa InvokeActionOperation
end

@testset "a shortcut is consumed by the shell, ahead of the focused child" begin
    fired = Ref(0)
    save  = Action("Save"; shortcut = Shortcut(:s; ctrl = true), callback = (_e) -> (fired[] += 1))
    shell = WidgetShell(WidgetLabel("body");
                        menu_bar = WidgetMenu([WidgetMenuItem(save)]),
                        size = Point2D(300, 200))
    sio = print_document(proj, shell)

    # The matching chord is consumed (returns the action op).
    @test read_intent(proj, sio, KeyDown(:s, ModifierKeys(ctrl = true), false)) isa InvokeActionOperation
    # A non-matching chord is not claimed as a shortcut (it falls through).
    @test !(read_intent(proj, sio, KeyDown(:x, ModifierKeys(ctrl = true), false)) isa InvokeActionOperation)
    # Exact-modifier matching: bare `s` (no Ctrl) is not the Ctrl+S shortcut.
    @test !(read_intent(proj, sio, KeyDown(:s, ModifierKeys(), false)) isa InvokeActionOperation)
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

@testset "a callback newer than the loop that presses it still runs" begin
    # `eval` makes the closure while this function runs, so it belongs to a newer
    # world than the function, as a closure typed into the evaluator or written
    # by the assistant is newer than the editor loop. The press must run it.
    fired = Ref(0)
    make_callback = Core.eval(Module(), :(counter -> () -> (counter[] += 1)))
    callback = Base.invokelatest(make_callback, fired)
    a = Action("X"; callback = callback)
    evaluate_operation(_ActionMockEditor(a), InvokeActionOperation(a))
    @test fired[] == 1
    takes_editor = Base.invokelatest(Core.eval(Module(), :(counter -> editor -> (counter[] += 10))), fired)
    b = Action("Y"; callback = takes_editor)
    evaluate_operation(_ActionMockEditor(b), InvokeActionOperation(b))
    @test fired[] == 11
end

@testset "a bound control is a LIVE view of its Action" begin
    # The property the whole design rests on: a control reads the action's cells
    # rather than owning copies, so renaming or disabling the command re-renders
    # every view of it with no re-binding step. Asserted on the DRAWN OUTPUT —
    # a structural check would pass against a frozen render.
    save = Action("Save"; callback = (_e) -> nothing)
    btn  = WidgetButton(save; size = Point2D(200, 0))
    item = WidgetMenuItem(save)
    bio, iio = print_document(proj, btn), print_document(proj, item)
    @test _dialog_text_xy(bio.output, "Save") !== nothing
    @test _dialog_text_xy(iio.output, "Save") !== nothing

    # Rename the command: both views follow, with nothing re-printed.
    save.label = "Store"
    @test _dialog_text_xy(bio.output, "Store") !== nothing
    @test _dialog_text_xy(iio.output, "Store") !== nothing
    @test _dialog_text_xy(bio.output, "Save")  === nothing

    # Disable it: both views decline the click (the conjunction's action half).
    save.enabled = false
    @test read_intent(proj, bio, MousePress(:left, 2, 2, ModifierKeys())) === nothing
    @test read_intent(proj, iio, MousePress(:left, 2, 2, ModifierKeys())) === nothing
    save.enabled = true
    @test read_intent(proj, bio, MousePress(:left, 2, 2, ModifierKeys())) isa InvokeActionOperation

    # The view's own gate is the other half: inert here, live elsewhere.
    btn.enabled = false
    @test read_intent(proj, bio, MousePress(:left, 2, 2, ModifierKeys())) === nothing
    @test read_intent(proj, iio, MousePress(:left, 2, 2, ModifierKeys())) isa CompoundOperation
end

@testset "a control's own label and icon fold into a fresh Action" begin
    f = (_e) -> nothing
    b = WidgetButton("Go"; size = Point2D(80, 0), action = f, icon = :save)
    @test b.action isa Action
    @test b.action.label === "Go" && b.action.icon === :save && b.action.callback === f
    # Two sugar-built controls never share an Action.
    @test WidgetButton("Go"; size = Point2D(80, 0)).action !==
          WidgetButton("Go"; size = Point2D(80, 0)).action
    # A sugar action declares no shortcut, so it never enters the shell registry.
    @test b.action.shortcut === nothing

    # A bound Action is the source of truth and is never written to: an own
    # label that says something ELSE has nowhere to live.
    save = Action("Save"; icon = :save, callback = f)
    @test WidgetButton(save; size = Point2D(80, 0)).action === save
    @test WidgetButton("Save"; size = Point2D(80, 0), action = save).action === save
    @test_throws ErrorException WidgetButton("Different"; size = Point2D(80, 0), action = save)
    @test_throws ErrorException WidgetButton(save; size = Point2D(80, 0), action = f)
end

@testset "a command that does something beats the dialog it also carries" begin
    fired = Ref(0)
    dlg = WidgetMessageBox("Confirm", "Proceed?")

    # Dialog alone: the click opens it.
    only_dialog = WidgetButton("Open"; size = Point2D(80, 0), dialog = dlg)
    dio = print_document(proj, only_dialog)
    @test read_intent(proj, dio, MousePress(:left, 2, 2, ModifierKeys())) isa OpenWindowOperation

    # Callback as well: the callback wins, and the dialog is the fallback for a
    # command that does nothing.
    both = WidgetButton("Open";
                        size = Point2D(80, 0), action = (_e) -> (fired[] += 1), dialog = dlg)
    bio = print_document(proj, both)
    @test read_intent(proj, bio, MousePress(:left, 2, 2, ModifierKeys())) isa InvokeActionOperation
end

@testset "a menu item's submenu beats its callback" begin
    # Unlike a button's dialog: opening the submenu is what a menu-bar entry IS.
    sub  = WidgetMenu([WidgetMenuItem("Leaf")])
    item = WidgetMenuItem("File"; action = (_e) -> error("must not fire"), submenu = sub)
    iio  = print_document(proj, item)
    @test read_intent(proj, iio, MousePress(:left, 2, 2, ModifierKeys())) isa OpenPopupOperation
end

@testset "WidgetStatusBar renders its segments as a bottom band" begin
    sb = WidgetStatusBar(["Ready", "Ln 1, Col 1"])
    iomap = print_document(proj, sb)
    @test iomap.output isa GraphicsCanvas
    @test Int(iomap.output.w[]) > 0
    # Both segments are drawn as text (helper defined in WidgetDialogTest).
    @test _dialog_text_xy(iomap.output, "Ready") !== nothing
    @test _dialog_text_xy(iomap.output, "Ln 1, Col 1") !== nothing
    # A status bar is inert.
    @test read_intent(proj, iomap, MousePress(:left, 2, 2, ModifierKeys())) === nothing
end

end # @testset
end # function
