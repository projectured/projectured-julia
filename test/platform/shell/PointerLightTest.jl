# The light under the pointer, through a real editor: a move writes the mouse
# target of the part under the pointer, and each widget draws its light from its
# own mouse target. The tests count the rects that the editor draws in the colour
# of the light, so they check what renders, not only what a reader answers.

const _PL_MEASURE = FixedMeasure(10, 18, 6, 0)

_pl_channels(color) = (color.red, color.green, color.blue, color.alpha)

# An editor over a window that shows `content` through the widget projection, and
# a function that moves the pointer to a point of the window.
function _pl_make_editor(content)
    scene = make_window_scene(content, "light"; width = 400, height = 300)
    projection = make_window_scene_projection(make_widget_projection_example(measure = _PL_MEASURE))
    tracked, tracking = make_tracking_screen(scene, projection)
    backend = HeadlessBackend()
    editor = Editor(tracked, tracking; backend = backend, devices = Device[Keyboard(), Mouse()])
    run_frame!(editor)
    time = Ref(0.0)
    move!(x, y) = (push_event!(backend, WindowInput(:light, MouseMove(x, y; time = time[] += 0.01)));
                   run_frame!(editor))
    (editor, move!)
end

# The number of rects with an area that the editor draws in the colour of the light.
function _pl_count_lights(editor)
    light = _pl_channels(WidgetModule._get_hover_layer(make_scaled_theme(make_widget_theme())))
    count = 0
    seen = IdDict{Any,Bool}()
    function visit(node)
        node isa AbstractCell && (node = node[])
        (node === nothing || node isa Number || node isa AbstractString || haskey(seen, node)) && return
        seen[node] = true
        if node isa GraphicsRect
            Int(node.w) > 0 && Int(node.h) > 0 && _pl_channels(node.color) == light && (count += 1)
            return
        end
        for name in (:elements, :content, :windows)
            hasproperty(node, name) || continue
            value = getproperty(node, name)
            value isa AbstractCell && (value = value[])
            value isa AbstractVector ? foreach(visit, value) : visit(value)
        end
    end
    visit(editor.iomap.output)
    count
end

_pl_path(steps...) = extend_reference(EmptyReference(), steps...)
_pl_element(field, i) = (FieldReferenceStep(field), ElementReferenceStep(i))

function test_pointer_light()
@testset "the part under the pointer lights, through a real editor" begin

@testset "a button lights while the pointer is on it" begin
    button = WidgetButton("Press"; size = Point2D(120, 40))
    editor, move! = _pl_make_editor(button)
    @test _pl_count_lights(editor) == 0
    move!(5, 5)
    @test get_mouse_target(button) == EmptyReference()
    @test _pl_count_lights(editor) == 1
    move!(390, 290)
    @test get_mouse_target(button) === nothing
    @test _pl_count_lights(editor) == 0
end

@testset "a disabled button does not light" begin
    button = WidgetButton("Off"; size = Point2D(120, 40), enabled = false)
    editor, move! = _pl_make_editor(button)
    move!(5, 5)
    @test get_mouse_target(button) == EmptyReference()
    @test _pl_count_lights(editor) == 0
end

@testset "a menu item and a toolbar item light" begin
    menu = WidgetMenu(Any[WidgetMenuItem("New"), WidgetMenuItem("Open")])
    editor, move! = _pl_make_editor(menu)
    move!(5, 50)
    @test get_mouse_target(menu) == _pl_path(_pl_element("elements", 2)...)
    @test _pl_count_lights(editor) == 1
    move!(390, 290)
    @test _pl_count_lights(editor) == 0

    toolbar = WidgetToolbar(Any[WidgetToolbarItem("Cut"), WidgetToolbarItem("Paste")])
    editor, move! = _pl_make_editor(toolbar)
    move!(60, 10)
    @test get_mouse_target(toolbar.elements[2]) == EmptyReference()
    @test get_mouse_target(toolbar.elements[1]) === nothing
    @test _pl_count_lights(editor) == 1
end

@testset "a list, a table and a tree light the row under the pointer" begin
    list = WidgetList(["one", "two", "three"]; width = 200)
    editor, move! = _pl_make_editor(list)
    move!(20, 55)
    @test get_mouse_target(list) == _pl_path(_pl_element("items", 2)...)
    @test _pl_count_lights(editor) == 1
    move!(390, 290)
    @test _pl_count_lights(editor) == 0

    table = WidgetTable(["A", "B"], [["1", "2"], ["3", "4"]])
    editor, move! = _pl_make_editor(table)
    move!(20, 60)
    @test get_mouse_target(table) == _pl_path(_pl_element("cells", 1)..., ElementReferenceStep(1))
    @test _pl_count_lights(editor) == 1
    # A column header lights its column.
    move!(5, 5)
    @test get_mouse_target(table) == _pl_path(_pl_element("column_headers", 1)...)
    @test _pl_count_lights(editor) == 1

    tree = WidgetTree(Any["alpha", "beta", ("gamma", Any["delta"])]; expanded = Set([[3]]))
    editor, move! = _pl_make_editor(tree)
    move!(20, 55)
    @test get_mouse_target(tree) == _pl_path(_pl_element("roots", 2)...)
    @test _pl_count_lights(editor) == 1
    move!(390, 290)
    @test _pl_count_lights(editor) == 0
end

end # @testset
end # test_pointer_light
