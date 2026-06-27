# WidgetDialog modal dialogs (Stage 3, Step 5). A WidgetDialog renders a scrim +
# centered card (title + content + button row). Dismissal: Esc, a backdrop click
# (on the scrim outside the card), or a button (its action fires AND the popup
# closes, in one CompoundOperation). Modality is enforced by WindowManager: while a
# modal window is open, envelopes routed to other windows are dropped. A
# WidgetButton with a `dialog` opens it as a modal window on click.

using Projectured: EventEnvelope, Change, KeyDown

mutable struct _DialogMockEditor
    document::Any
end

# Absolute (x, y) of the first GraphicsText whose text == `target`, summing nested
# canvas origins (a click at its origin reliably lands on the enclosing widget).
function _dialog_text_xy(canvas, target)
    _gi(v) = Int(v isa Projectured.ReactiveModule.Cell ? v[] : v)
    for el in canvas.elements
        el = el isa Projectured.ReactiveModule.Cell ? el[] : el
        if el isa GraphicsText
            string(el.text) == target && return (_gi(el.x), _gi(el.y))
        elseif el isa GraphicsCanvas
            sub = _dialog_text_xy(el, target)
            sub === nothing || return (sub[1] + _gi(el.x), sub[2] + _gi(el.y))
        end
    end
    nothing
end

function test_widget_dialog()
@testset "WidgetDialog (modal)" begin

proj = make_widget_projection_example()

# ── Dialog reader: dismissal paths ────────────────────────────────────────────

@testset "Esc dismisses the dialog" begin
    dlg = WidgetMessageBox("Title", "A message")
    iomap = projection_print(proj, dlg)
    op = projection_read(proj, iomap, KeyDown(:escape, Modifiers(), false))
    @test op isa CloseWindowOperation
    @test op.id === :widget_dialog
end

@testset "a backdrop click (on the scrim, outside the card) dismisses" begin
    dlg = WidgetMessageBox("Title", "A message")
    iomap = projection_print(proj, dlg)
    # (2, 2) is the top-left scrim; the card is centered, so it is outside it.
    op = projection_read(proj, iomap, MousePress(:left, 2, 2, Modifiers()))
    @test op isa CloseWindowOperation
    @test op.id === :widget_dialog
end

@testset "a button click runs its action and closes the dialog" begin
    fired = Ref(0)
    ok = WidgetButton(Point2D(0, 0), Point2D(72, 0), "OK"; action = (_e) -> (fired[] += 1))
    dlg = WidgetDialog("Confirm", WidgetLabel(Point2D(0, 0), "Proceed?"), Any[ok])
    iomap = projection_print(proj, dlg)
    xy = _dialog_text_xy(iomap.output, "OK")
    @test xy !== nothing
    op = projection_read(proj, iomap, MousePress(:left, xy[1] + 2, xy[2] + 2, Modifiers()))
    @test op isa CompoundOperation
    @test op.operations[1] isa InvokeWidgetActionOperation
    @test op.operations[2] isa CloseWindowOperation
    @test op.operations[2].id === :widget_dialog
    evaluate_operation(_DialogMockEditor(dlg), op.operations[1])
    @test fired[] == 1
end

@testset "a custom popup_id is the id that closes" begin
    dlg = WidgetMessageBox("T", "m"; popup_id = :my_dialog)
    iomap = projection_print(proj, dlg)
    op = projection_read(proj, iomap, KeyDown(:escape, Modifiers(), false))
    @test op isa CloseWindowOperation
    @test op.id === :my_dialog
end

# ── Modality: WindowManager drops input to non-modal windows ──────────────────

@testset "a modal window blocks input to other windows" begin
    select = WidgetSelect(Point2D(0, 0), "Apple"; options=["Apple", "Banana"], width=160)
    base   = WindowDocument(; id=:base, x=0, y=0, width=300, height=200,
                            content=VerticalLayout(Any[select]; horizontal_align=:left))
    dlg    = WidgetMessageBox("Hi", "Modal!")        # popup_id defaults to :widget_dialog
    modal  = WindowDocument(; id=:widget_dialog, x=40, y=40, width=480, height=320,
                            modal=true, content=dlg)
    screen = ScreenDocument([base, modal])
    sproj  = make_widget_popup_projection_example()
    iomap  = projection_print(sproj, screen)

    nbefore = length(screen.windows)
    # Clicking the select in the BASE window would normally open a dropdown popup;
    # while the modal is open the envelope is dropped, so no window opens.
    env = EventEnvelope(:base, MousePress(:left, 10, 10, Modifiers()))
    projection_read(sproj, nothing, Change(env, nothing), iomap)
    @test length(screen.windows) == nbefore

    # Esc routed to the modal window itself IS processed → it closes.
    env2 = EventEnvelope(:widget_dialog, KeyDown(:escape, Modifiers(), false))
    projection_read(sproj, nothing, Change(env2, nothing), iomap)
    @test !any(w -> w isa WindowDocument && w.id === :widget_dialog, screen.windows)
end

# ── Opening a dialog from a button ────────────────────────────────────────────

@testset "a button with a dialog opens it as a modal window" begin
    dlg  = WidgetMessageBox("Confirm", "Sure?")
    btn  = WidgetButton(Point2D(0, 0), Point2D(120, 40), "Open"; dialog = dlg)
    base = WindowDocument(; id=:base, x=0, y=0, width=300, height=200,
                          content=VerticalLayout(Any[btn]; horizontal_align=:left))
    screen = ScreenDocument([base])
    sproj  = make_widget_popup_projection_example()
    iomap  = projection_print(sproj, screen)

    nbefore = length(screen.windows)
    env = EventEnvelope(:base, MousePress(:left, 10, 10, Modifiers()))
    projection_read(sproj, nothing, Change(env, nothing), iomap)
    @test length(screen.windows) == nbefore + 1
    opened = nothing
    for w in screen.windows
        w isa WindowDocument && w.modal === true && (opened = w)
    end
    @test opened !== nothing
    @test opened.id === :widget_dialog
    @test opened.content isa WidgetDialog
end

end # @testset
end # function
