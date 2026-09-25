# The four Alt + arrow keys walk a whole selection over the structure of any
# document: up to the enclosing object, down to the first object inside, and
# sideways to the siblings. A reader inside answers first.

# An item that holds a holder, which the walk passes through to its two parts.
@document struct _WalkHolder <: Document
    first::Any
    second::Any
end
FocusModule.is_selection_walk_stop(::_WalkHolder) = false
@document struct _WalkItem <: Document
    holder::Any
end

function _walking_tree()
    button = WidgetButton("Go"; size = Point2D(120, 40))
    label = WidgetLabel("hello")
    field = WidgetText("typed")
    layout = VerticalLayout(Any[button, label, field]; gap = 10)
    card = WidgetCard(; title = "Title", content = layout)
    root = WidgetComposite(Any[card])
    (root = root, card = card, layout = layout, button = button, label = label, field = field)
end

_walk_key(key, modifiers = ModifierKeys(alt = true)) = KeyDown(key, modifiers; time = 0.0)

# Where one step of the walk from `node` lands, as the node it names.
function _walk_from(root, node, direction)
    selection = _walking_path(root, node)
    path = compute_selection_walk(root, selection, direction)
    path === nothing ? nothing : evaluate_reference(root, path)
end

# The whole-selection path of `node` inside `root`, found by the walk down and
# sideways, so the test does not spell a path by hand.
function _walking_path(root, node)
    node === root && return EmptyReference()
    frontier = Any[EmptyReference()]
    while !isempty(frontier)
        path = popfirst!(frontier)
        evaluate_reference(root, path) === node && return path
        down = compute_selection_walk(root, path, :down)
        (down === nothing || down == path) && continue
        sibling = down
        seen = Set{String}()
        while !(string(sibling) in seen)
            push!(seen, string(sibling))
            push!(frontier, sibling)
            sibling = compute_selection_walk(root, sibling, :right)
        end
    end
    error("the walk does not reach the node")
end

# A projection that answers Alt+Up with a fixed selection, and nothing else.
struct _WalkAnsweringProjection <: Projection
    answer::Any
end
ProjectionModule.print_document(p::_WalkAnsweringProjection, recursion, input, ctx) =
    SimpleIoMap(p, input, input)
ProjectionModule.read_intent(p::_WalkAnsweringProjection, recursion, change::Intent, iomap) =
    Intent(change.gesture, change.gesture == _walk_key(:up) ? p.answer : nothing)

function test_selection_walking()
    @testset "Alt+Down and Alt+Right reach every object, and skip values" begin
        t = _walking_tree()
        @test _walk_from(t.root, t.root, :down) === t.card
        @test _walk_from(t.root, t.card, :down) === t.layout
        @test _walk_from(t.root, t.layout, :down) === t.button
        @test _walk_from(t.root, t.button, :right) === t.label
        @test _walk_from(t.root, t.label, :right) === t.field
        # At the ends of the row the selection stays.
        @test _walk_from(t.root, t.field, :right) === t.field
        @test _walk_from(t.root, t.button, :left) === t.button
        @test _walk_from(t.root, t.label, :left) === t.button
        # A label holds a text style, which is a value and not an object, so
        # there is nothing inside to go down to.
        @test _walk_from(t.root, t.label, :down) === t.label
    end

    @testset "Alt+Up reaches the enclosing object, up to the root" begin
        t = _walking_tree()
        @test _walk_from(t.root, t.label, :up) === t.layout
        @test _walk_from(t.root, t.layout, :up) === t.card
        @test _walk_from(t.root, t.card, :up) === t.root
        @test compute_selection_walk(t.root, EmptyReference(), :up) === nothing
    end

    @testset "the walk passes through a document that is not a stop" begin
        first, second = PrimitiveString("a"), PrimitiveString("b")
        item = _WalkItem(_WalkHolder(first, second))
        walk(path, direction) = begin
            found = compute_selection_walk(item, path, direction)
            found === nothing ? nothing : evaluate_reference(item, found)
        end
        at_first = compute_selection_walk(item, EmptyReference(), :down)
        @test evaluate_reference(item, at_first) === first
        at_second = compute_selection_walk(item, at_first, :right)
        @test evaluate_reference(item, at_second) === second
        @test walk(at_second, :left) === first
        @test walk(at_second, :right) === second
        # Up skips the holder and reaches the item.
        @test compute_selection_walk(item, at_second, :up) == EmptyReference()
        @test !is_selection_walk_stop(item.holder)
        @test is_selection_walk_stop(item)
    end

    @testset "a caret goes up to its object, and sideways nowhere" begin
        text = PrimitiveString("abc")
        holder = WidgetComposite(Any[WidgetLabel("x")])
        caret = ConcreteReference(RangeReferenceStep(1, 1), EmptyReference())
        @test compute_selection_walk(text, caret, :up) == EmptyReference()
        @test compute_selection_walk(text, caret, :left) === nothing
        @test compute_selection_walk(text, caret, :right) === nothing
        @test compute_selection_walk(text, caret, :down) === nothing
        @test compute_selection_walk(holder, nothing, :up) === nothing
    end

    @testset "only an arrow with Alt alone is a walk" begin
        @test get_selection_walk_direction(_walk_key(:left)) === :left
        @test get_selection_walk_direction(_walk_key(:up)) === :up
        @test get_selection_walk_direction(_walk_key(:left, ModifierKeys())) === nothing
        @test get_selection_walk_direction(_walk_key(:left, ModifierKeys(alt = true, ctrl = true))) === nothing
        @test get_selection_walk_direction(_walk_key(:home)) === nothing
        @test get_selection_walk_direction(MousePress(:left, 1, 1, ModifierKeys(alt = true); time = 0.0)) === nothing
    end

    @testset "the projection answers what nothing inside answered" begin
        t = _walking_tree()
        label_path = _walking_path(t.root, t.label)
        replace_selection!(t.root, label_path)
        fixed = ReplaceSelectionOperation(EmptyReference())
        projection = SelectionWalkingProjection(inner = _WalkAnsweringProjection(fixed))
        iomap = print_document(projection, projection, t.root, PrinterContext())
        # The inner reader answers Alt+Up, and its answer is kept.
        @test read_intent(projection, iomap, _walk_key(:up)) === fixed
        # It does not answer Alt+Right, so the walk does.
        right = read_intent(projection, iomap, _walk_key(:right))
        @test right isa ReplaceSelectionOperation
        @test evaluate_reference(t.root, right.path) === t.field
        # A key that is not a walk is left alone.
        @test read_intent(projection, iomap, _walk_key(:right, ModifierKeys())) === nothing
        # The wrapper prints as its inner projection.
        @test iomap.output === t.root
    end
end
