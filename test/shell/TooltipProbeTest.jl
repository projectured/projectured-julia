# The probe that shows what the document under the pointer says about itself.
#
# It is read through a real window scene, because what it answers is a window
# operation and the window manager is what applies one. A tooltip is a window of
# its own on every backend — PAR-MANY-WINDOWS — so the proof is the window that
# appears, not the operation that comes back.

function test_tooltip_probe()
@testset "the tooltip probe" begin

_pointer() = (300, 400)

# A widget that says something, and one that says nothing, side by side.
_content() = VerticalLayout(Any[
    WidgetLabel(Point2D(0, 0), "speaks"; tooltip = "what this label is for"),
    WidgetLabel(Point2D(0, 40), "silent"),
])

function _scene_and_projection(; tooltip = compute_tooltip)
    document, projection = make_window_wrap(;
        gesture_help = false, command_palette = false, gesture_log = false,
        selection = false, tooltip = tooltip,
        pointer = _pointer)(_content(), make_layout_projection_example())
    scene = make_window_scene(document, "shell"; width = 400, height = 300)
    composed = make_window_scene_projection(projection;
        opened_window_projections = make_opened_window_projections())
    (scene, composed)
end

_move(composed, scene, x, y) = begin
    iomap = print_document(composed, scene)
    change = read_intent(composed, nothing,
                         Intent(WindowInput(:shell, MouseMove(x, y))),
                         iomap)
    change isa Intent ? change.operation : change
end

@testset "a document that says something opens a window of its own" begin
    scene, composed = _scene_and_projection()
    @test length(scene.windows) == 1
    _move(composed, scene, 20, 10)
    @test length(scene.windows) == 2
    tip = last(scene.windows)
    # Its own window, beside the pointer, in the style a tooltip is given.
    @test tip.style === :tooltip
    @test tip.x == 300 + 16 && tip.y == 400 + 20
    @test tip.content isa PrimitiveString
    @test tip.content.value == "what this label is for"
end

@testset "a document that says nothing opens none" begin
    scene, composed = _scene_and_projection()
    _move(composed, scene, 20, 50)
    @test length(scene.windows) == 1
end

@testset "the same document says it once" begin
    scene, composed = _scene_and_projection()
    _move(composed, scene, 20, 10)
    @test length(scene.windows) == 2
    # A pointer crossing the same label re-opens nothing: the answer has not
    # changed, so the probe stays quiet.
    @test _move(composed, scene, 26, 12) === nothing
    @test length(scene.windows) == 2
end

@testset "leaving the document closes the window" begin
    scene, composed = _scene_and_projection()
    _move(composed, scene, 20, 10)
    @test length(scene.windows) == 2
    _move(composed, scene, 20, 50)
    @test length(scene.windows) == 1
end

@testset "no tooltip function, no probe" begin
    scene, composed = _scene_and_projection(tooltip = nothing)
    _move(composed, scene, 20, 10)
    @test length(scene.windows) == 1
end

@testset "a tooltip needs somewhere to go" begin
    @test_throws ErrorException make_window_wrap(; tooltip = compute_tooltip)
end

end # @testset
end # function
