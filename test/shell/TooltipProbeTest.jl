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

# What draws what a tooltip holds. A window whose content type is named by no row
# opens and draws nothing, so a host that turns the tooltip on passes the rows
# for its own documents.
_tooltip_content() = Pair{Type,Any}[
    PrimitiveDocument => ChainingProjection(RecursiveProjection(PrimitiveToText()),
                                            TextToGraphics(measure = measure_truetype_text))]

function _scene_and_projection(; tooltip = compute_tooltip, content = _tooltip_content())
    document, projection = make_window_wrap(;
        gesture_help = false, command_palette = false,
        selection = false, tooltip = tooltip,
        pointer = _pointer)(_content(), make_layout_projection_example())
    scene = make_window_scene(document, "shell"; width = 400, height = 300)
    composed = make_window_scene_projection(projection;
        opened_window_projections = make_opened_window_projections(; content = content))
    (scene, composed)
end

# Every string a printed window holds, so a case can ask what was drawn rather
# than what was stored.
function _drawn_strings(node, found = String[])
    node === nothing && return found
    if hasproperty(node, :elements)
        for element in node.elements
            _drawn_strings(element, found)
        end
    elseif hasproperty(node, :text) && node.text isa AbstractString
        push!(found, String(node.text))
    elseif hasproperty(node, :content)
        _drawn_strings(node.content, found)
    end
    found
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

@testset "the window draws what the document said" begin
    scene, composed = _scene_and_projection()
    _move(composed, scene, 20, 10)
    output = print_document(composed, scene).output
    @test any(text -> occursin("what this label is for", text),
              _drawn_strings(output.windows[end].content))
end

# A tooltip is a document of the host's own domains, and the window that holds
# one draws nothing when the host named no row for it.
@testset "no row for what it holds, and it draws nothing" begin
    scene, composed = _scene_and_projection(; content = Pair{Type,Any}[])
    _move(composed, scene, 20, 10)
    output = print_document(composed, scene).output
    @test isempty(_drawn_strings(output.windows[end].content))
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

# The right press asks the same document the same kind of question, and what it
# answers opens through the popup route a menu already takes.

function test_context_menu_probe()
@testset "the context menu probe" begin

# `context_menu` is a field of the window's own frame and of nothing else, so
# the shell is what carries one. Every other document computes its menu.
_speaks() = WidgetShell(WidgetLabel(Point2D(0, 0), "speaks");
                        size = Point2D(200, 100),
                        context_menu = WidgetMenu([WidgetMenuItem("Copy"),
                                                   WidgetMenuItem("Paste")]))

function _read(document; menu = compute_context_menu)
    _, projection = make_window_wrap(;
        gesture_help = false, command_palette = false,
        selection = false, context_menu = menu)(document, make_layout_projection_example())
    iomap = print_document(projection, document)
    answer = read_intent(projection, nothing,
                         Intent(MousePress(:right, 5, 5, ModifierKeys())), iomap)
    answer isa Intent ? answer.operation : answer
end

@testset "a document that offers a menu opens one" begin
    operation = _read(_speaks())
    @test operation isa OpenPopupOperation
    @test operation.content isa WidgetMenu
    # A popup with no size is a window nobody sees.
    @test operation.width > 0 && operation.height > 0
end

@testset "a document that offers none opens none" begin
    @test !(_read(WidgetShell(WidgetLabel(Point2D(0, 0), "silent");
                              size = Point2D(200, 100))) isa OpenPopupOperation)
end

@testset "no function, no probe" begin
    @test !(_read(_speaks(); menu = nothing) isa OpenPopupOperation)
end

end # @testset
end # function
