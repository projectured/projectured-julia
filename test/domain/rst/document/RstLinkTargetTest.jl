# What the target of an rst reference names, for a navigator: the part after an
# `.. _name:` target, a section by its title, a file beside the file of the
# document, and nothing for a URL.

function test_rst_link_target()
@testset "rst link targets" begin
    source = """
    Guide
    =====

    .. _ug:cha:queueing:

    Queueing
    --------

    Text.

    Routing Tables
    --------------

    More.
    """
    root = parse_rst(source)
    guide = root.elements[1]
    @test guide isa RstSection
    found = find_navigator_target(root, "ug:cha:queueing")
    @test found !== nothing
    @test evaluate_reference(root, found) isa RstSection
    @test get_rst_title_text(evaluate_reference(root, found)) == "Queueing"
    # A section by its title, as rst compares names: no case, one space.
    found = find_navigator_target(root, "routing   tables")
    @test get_rst_title_text(evaluate_reference(root, found)) == "Routing Tables"
    @test find_navigator_target(root, "nothing") === nothing
    folder = mktempdir()
    write(joinpath(folder, "other.rst"), "Other\n=====\n")
    file = RstFile(joinpath(folder, "index.rst"), root)
    @test get_rst_title_text(evaluate_reference(file, find_navigator_target(file, "Queueing"))) == "Queueing"
    @test find_navigator_target(file, "other.rst") == joinpath(folder, "other.rst")
    @test find_navigator_target(file, "https://omnetpp.org") === nothing
end
end

# A document with a named reference to a target below it.
const _RST_LINK_SOURCE = """
Guide
=====

See `queueing`_ for more.

.. _queueing:

Queueing
--------

Text.
"""

# The open in an answer, inside a compound or a wrapper, or `nothing`.
_find_rst_open(operation::OpenPageOperation) = operation
_find_rst_open(operation::WrappingOperation) = _find_rst_open(get_wrapped_operation(operation))
_find_rst_open(operation::CompoundOperation) =
    something((_find_rst_open(member) for member in operation.operations)..., nothing)
_find_rst_open(::Any) = nothing

# An editor that draws `root` with `projection`, and the answer to an event.
function _make_rst_link_editor(root, projection)
    backend = HeadlessBackend()
    editor = build_editor(root, projection; backend, devices = Device[Keyboard(), Mouse(), Display()],
                          window = false, tabs = false, appearance = false, settings = false)
    run_frame!(editor)
    answer(event) = _find_rst_open(read_intent(editor.projection, nothing, Intent(event), editor.iomap).operation)
    (editor, backend, answer)
end

function test_rst_link_gestures()
@testset "rst link gestures" begin
    platform = ProjecturedPlatformTest
    measure = FixedMeasure(8, 12, 4, 0)
    with(click; ctrl = false, shift = false) =
        MouseClick(:left, click.x, click.y, 1, ModifierKeys(; ctrl, shift); time = 0.0)

    @testset "the source view follows on Ctrl+click and Ctrl+Shift+click, and a click puts the caret" begin
        editor, backend, answer = _make_rst_link_editor(parse_rst(_RST_LINK_SOURCE),
                                                        make_rst_projection_example(; measure))
        click = platform._nav_click(backend, "queueing")
        @test click !== nothing
        followed = answer(with(click; ctrl = true))
        @test followed !== nothing && followed.target == "queueing" && followed.place === :here
        @test answer(with(click; ctrl = true, shift = true)).place === :new_tab
        @test answer(click) === nothing
    end

    @testset "the rendered view follows on a click, and opens a new tab on Ctrl+click" begin
        editor, backend, answer = _make_rst_link_editor(parse_rst(_RST_LINK_SOURCE),
                                                        make_rst_rendered_projection_example(; measure))
        click = platform._nav_click(backend, "queueing")
        @test click !== nothing
        @test answer(click).place === :here
        @test answer(with(click; ctrl = true)).place === :new_tab
    end

    @testset "the rendered page of a navigator follows a reference on a click" begin
        root = parse_rst(_RST_LINK_SOURCE)
        navigator = Navigator(root)
        editor, backend = platform._nav_editor(navigator)
        platform._nav_press!(editor, backend, platform._nav_click(backend, "queueing"))
        page = get_navigator_page(navigator)
        @test page isa RstSection && get_rst_title_text(page) == "Queueing"
        @test length(navigator.back) == 1
    end

    @testset "the rendered page shows the hand over a reference, and the I-beam over its text" begin
        editor, backend = platform._nav_editor(Navigator(parse_rst(_RST_LINK_SOURCE)))
        canvas = last(rendered_output(backend))
        @test find_pointer_shape(canvas, platform._nav_click(backend, "queueing").x,
                                 platform._nav_click(backend, "queueing").y) === :pointing_hand
        see = platform._nav_click(backend, "See ")
        @test find_pointer_shape(canvas, see.x, see.y) === :ibeam
    end

    @testset "the tooltip of a reference shows its target" begin
        root = parse_rst(_RST_LINK_SOURCE)
        paragraph = root.elements[1].elements[1]
        reference = only(child for child in paragraph.content if child isa RstReference)
        opened = get_wrapped_operation(read_gesture(reference, MouseDwell(0, 0; time = 0.0)))
        (_, content) = only(opened.layers)
        @test content isa PrimitiveString && content.value == "queueing"
    end
end
end
