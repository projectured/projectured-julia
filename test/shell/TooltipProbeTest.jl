# The probe that shows what the document under the pointer says about itself,
# once the pointer has rested there.
#
# It is read through a real window scene, because what it answers is a window
# operation and the window manager is what applies one. A tooltip is a window of
# its own on every backend — PAR-MANY-WINDOWS — so the proof is the window that
# appears, not the operation that comes back.
#
# A rest is what the window's `TooltipFeed` reads when its deadline passes: a
# `PointerRest` at the place the pointer last moved to. `_rest` reads it the way
# the feed does, through the window's whole projection; `test_tooltip_feed`
# drives the feed itself.

_tooltip_pointer() = (300, 400)

# A widget that says something, and one that says nothing, side by side.
_tooltip_labels() = VerticalLayout(Any[
    WidgetLabel(Point2D(0, 0), "speaks"; tooltip = "what this label is for"),
    WidgetLabel(Point2D(0, 40), "silent"),
])

# What draws what a tooltip holds. A window whose content type is named by no row
# opens and draws nothing, so a host that turns the tooltip on passes the rows
# for its own documents.
_tooltip_content() = Pair{Type,Any}[
    PrimitiveDocument => ChainingProjection(RecursiveProjection(PrimitiveToText()),
                                            TextToGraphics(measure = measure_truetype_text))]

function _tooltip_scene(; tooltip = compute_tooltip, content = _tooltip_content(),
                          feed = make_tooltip_feed(now = () -> 0.0),
                          document = _tooltip_labels())
    document, projection = make_window_wrap(;
        gesture_help = false, command_palette = false,
        selection = false, tooltip = tooltip, pointer = _tooltip_pointer,
        tooltip_feed = tooltip === nothing ? nothing : feed)(document,
                                                             make_layout_projection_example())
    scene = make_window_scene(document, "shell"; width = 400, height = 300)
    composed = make_window_scene_projection(projection;
        opened_window_projections = make_opened_window_projections(; content = content))
    (scene, composed, feed)
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

function _tooltip_read(composed, scene, event)
    change = read_intent(composed, nothing, Intent(WindowInput(:shell, event)),
                         print_document(composed, scene))
    change isa Intent ? change.operation : change
end

_move(composed, scene, x, y) = _tooltip_read(composed, scene, MouseMove(x, y))
_rest(composed, scene, feed) =
    _tooltip_read(composed, scene, PointerRest(feed.rest.x, feed.rest.y))

# Whether an operation is, or holds, one of type `T`.
_holds_operation(op, T) =
    op isa T ||
    (op isa CompoundOperation && any(o -> _holds_operation(o, T), op.operations)) ||
    (op isa WrappingOperation && _holds_operation(get_wrapped_operation(op), T))

function test_tooltip_probe()
@testset "the tooltip probe" begin

@testset "a move alone opens nothing" begin
    scene, composed, _ = _tooltip_scene()
    _move(composed, scene, 20, 10)
    @test length(scene.windows) == 1
end

@testset "a rest on a document that says something opens a window of its own" begin
    scene, composed, feed = _tooltip_scene()
    _move(composed, scene, 20, 10)
    _rest(composed, scene, feed)
    @test length(scene.windows) == 2
    tip = last(scene.windows)
    # Its own window, beside the pointer, in the style a tooltip is given.
    @test tip.style === :tooltip
    @test tip.x == 300 + 16 && tip.y == 400 + 20
    @test tip.content isa PrimitiveString
    @test tip.content.value == "what this label is for"
    # It says its bounds rather than a size: it is printed at the maximum, and
    # the backend gives it the extent of what it printed, never below the
    # minimum.
    @test tip.minimum_size == (120, 32)
    @test tip.maximum_size == (560, 400)
end

@testset "the window draws what the document said" begin
    scene, composed, feed = _tooltip_scene()
    _move(composed, scene, 20, 10)
    _rest(composed, scene, feed)
    output = print_document(composed, scene).output
    @test any(text -> occursin("what this label is for", text),
              _drawn_strings(output.windows[end].content))
end

# A tooltip is a document of the host's own domains, and the window that holds
# one draws nothing when the host named no row for it.
@testset "no row for what it holds, and it draws nothing" begin
    scene, composed, feed = _tooltip_scene(; content = Pair{Type,Any}[])
    _move(composed, scene, 20, 10)
    _rest(composed, scene, feed)
    output = print_document(composed, scene).output
    @test isempty(_drawn_strings(output.windows[end].content))
end

@testset "a rest on a document that says nothing opens none" begin
    scene, composed, feed = _tooltip_scene()
    _move(composed, scene, 20, 50)
    _rest(composed, scene, feed)
    @test length(scene.windows) == 1
end

@testset "a second rest opens no second window" begin
    scene, composed, feed = _tooltip_scene()
    _move(composed, scene, 20, 10)
    _rest(composed, scene, feed)
    @test _rest(composed, scene, feed) === nothing
    @test length(scene.windows) == 2
end

@testset "a move away closes the window, and a small one keeps it" begin
    scene, composed, feed = _tooltip_scene()
    _move(composed, scene, 20, 10)
    _rest(composed, scene, feed)
    _move(composed, scene, 22, 11)
    @test length(scene.windows) == 2
    _move(composed, scene, 20, 50)
    @test length(scene.windows) == 1
end

@testset "a press closes the window" begin
    scene, composed, feed = _tooltip_scene()
    _move(composed, scene, 20, 10)
    _rest(composed, scene, feed)
    _tooltip_read(composed, scene, MousePress(:left, 20, 10, 1, ModifierKeys()))
    @test length(scene.windows) == 1
end

# The probe only watches the pointer: a move goes on to the readers inside, so a
# divider held under the probe still follows it.
@testset "a move passes on to the readers inside" begin
    split = WidgetSplitPane(:horizontal, Any[WidgetLabel(Point2D(0, 0), "left"),
                                             WidgetLabel(Point2D(0, 0), "right")];
                            sizes = [150, 150])
    scene, composed, _ = _tooltip_scene(; document = split)
    grab = nothing
    for x in 0:399
        operation = _tooltip_read(composed, scene, MouseDown(:left, x, 100))
        _holds_operation(operation, StartSplitterDragOperation) && (grab = (x, operation); break)
    end
    @test grab !== nothing
    (x, operation) = grab
    evaluate_operation(nothing, operation)
    moved = _tooltip_read(composed, scene, MouseMove(x + 30, 100, :left, ModifierKeys()))
    @test _holds_operation(moved, ResizeSplitPaneOperation)
end

@testset "no tooltip function, no probe" begin
    scene, composed, feed = _tooltip_scene(; tooltip = nothing)
    _move(composed, scene, 20, 10)
    _rest(composed, scene, feed)
    @test length(scene.windows) == 1
end

@testset "a tooltip needs somewhere to go and a clock to wait with" begin
    @test_throws ErrorException make_window_wrap(; tooltip = compute_tooltip)
    @test_throws ErrorException make_window_wrap(; tooltip = compute_tooltip,
                                                   pointer = _tooltip_pointer)
end

end # @testset
end # function

# The feed that keeps the tooltip's time, in a real editor: it names a deadline
# once the pointer stops, the loop would sleep until it, and at the deadline the
# feed posts what the probe answers to the rest.
function test_tooltip_feed()
@testset "the tooltip feed" begin
    clock = Ref(10.0)
    feed = make_tooltip_feed(; delay = 0.5, now = () -> clock[])
    scene, composed, _ = _tooltip_scene(; feed = feed)
    backend = HeadlessBackend()
    editor = Editor(backend, scene, composed, Device[Keyboard(), Mouse()];
                    feeds = Feed[feed])
    run_frame!(editor)
    press!(event) = (push_event!(backend, WindowInput(:shell, event)); run_frame!(editor))

    @testset "no move, no deadline" begin
        @test compute_wake_deadline(feed, editor) === nothing
    end

    @testset "a move names a deadline, and a later move moves it" begin
        press!(MouseMove(20, 10))
        @test compute_wake_deadline(feed, editor) ≈ 0.5
        clock[] = 10.3
        @test compute_wake_deadline(feed, editor) ≈ 0.2
        press!(MouseMove(21, 10))
        @test compute_wake_deadline(feed, editor) ≈ 0.5
    end

    @testset "before the deadline nothing opens" begin
        @test drain_changes!(feed, editor) == 0
        drain_feeds!(editor)
        @test length(scene.windows) == 1
    end

    @testset "at the deadline the window opens, and nothing more is due" begin
        clock[] = 10.9
        @test compute_wake_deadline(feed, editor) == 0
        drain_feeds!(editor)    # the feed posts what the probe answers
        drain_feeds!(editor)    # the inbox applies it
        @test length(scene.windows) == 2
        @test last(scene.windows).style === :tooltip
        @test compute_wake_deadline(feed, editor) === nothing
    end

    @testset "a move away closes it, and the wait starts again" begin
        press!(MouseMove(20, 50))
        @test length(scene.windows) == 1
        @test compute_wake_deadline(feed, editor) ≈ 0.5
    end
end
end

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
