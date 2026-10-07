# What the target of a markdown link names, for a navigator: a heading by its
# slug, a file beside the file of the page, and nothing for a URL.

function test_markdown_link_target()
@testset "markdown link targets" begin
    source = "# Projectured\n\nIntro.\n\n## Install the editor\n\nSteps.\n\n## Use it_now!\n"
    root = parse_markdown(source)
    headings = [element for element in root.elements if element isa MarkdownHeading]
    @test compute_markdown_heading_slug(headings[2]) == "install-the-editor"
    @test compute_markdown_heading_slug(headings[3]) == "use-it_now"
    found = find_navigator_target(root, "#install-the-editor")
    @test evaluate_reference(root, found) === headings[2]
    @test find_navigator_target(root, "#nothing-here") === nothing
    @test find_navigator_target(root, "guide.md") === nothing
    # A file names its headings, and a file beside it that exists.
    folder = mktempdir()
    write(joinpath(folder, "guide.md"), "# Guide\n")
    file = MarkdownFile(joinpath(folder, "readme.md"), root)
    @test evaluate_reference(file, find_navigator_target(file, "#use-it_now")) === headings[3]
    @test find_navigator_target(file, "guide.md") == joinpath(folder, "guide.md")
    @test find_navigator_target(file, "guide.md#guide") == joinpath(folder, "guide.md")
    @test find_navigator_target(file, "missing.md") === nothing
    @test find_navigator_target(file, "https://example.org/guide.md") === nothing
    @test find_navigator_target(file, "mailto:someone@example.org") === nothing
end
end

# A page with a link to a heading below it.
const _MARKDOWN_LINK_SOURCE = "# Guide\n\nRead the [setup](#install-it) part.\n\n## Install it\n\nSteps.\n"

# The open in an answer, inside a compound or a wrapper, or `nothing`.
_find_markdown_open(operation::OpenPageOperation) = operation
_find_markdown_open(operation::WrappingOperation) = _find_markdown_open(get_wrapped_operation(operation))
_find_markdown_open(operation::CompoundOperation) =
    something((_find_markdown_open(member) for member in operation.operations)..., nothing)
_find_markdown_open(::Any) = nothing

function test_markdown_link_gestures()
@testset "markdown link gestures" begin
    platform = ProjecturedPlatformTest

    @testset "the rendered page of a navigator follows a link on a click" begin
        root = parse_markdown(_MARKDOWN_LINK_SOURCE)
        navigator = Navigator(root)
        editor, backend = platform._nav_editor(navigator)
        platform._nav_press!(editor, backend, platform._nav_click(backend, "setup"))
        @test get_navigator_page(navigator) === root.elements[3]
        @test length(navigator.back) == 1
    end

    @testset "Ctrl+click on the rendered page opens the target in a new tab" begin
        root = parse_markdown(_MARKDOWN_LINK_SOURCE)
        navigator = Navigator(root)
        editor, backend = platform._nav_editor(navigator; tabs = true)
        platform._nav_press!(editor, backend, platform._nav_ctrl_click(platform._nav_click(backend, "setup")))
        drain_operations!(editor)
        run_frame!(editor)
        tabs = editor.document.root.tabs
        @test length(tabs) == 2
        @test get_navigator_page(tabs[2].content) === root.elements[3]
        @test navigator.address isa EmptyReference
    end

    @testset "the source view follows on Ctrl+click and Ctrl+Shift+click, and a click puts the caret" begin
        root = parse_markdown(_MARKDOWN_LINK_SOURCE)
        backend = HeadlessBackend()
        editor = build_editor(root, make_markdown_projection_example(; measure = FixedMeasure(8, 12, 4, 0));
                              backend, devices = Device[Keyboard(), Mouse(), Display()],
                              window = false, tabs = false, appearance = false, settings = false)
        run_frame!(editor)
        click = platform._nav_click(backend, "setup")
        @test click !== nothing
        answer(event) = read_intent(editor.projection, nothing, Intent(event), editor.iomap).operation
        followed = _find_markdown_open(answer(platform._nav_ctrl_click(click)))
        @test followed !== nothing && followed.target == "#install-it" && followed.place === :here
        both = MouseClick(:left, click.x, click.y, 1, ModifierKeys(ctrl = true, shift = true); time = 0.0)
        @test _find_markdown_open(answer(both)).place === :new_tab
        @test _find_markdown_open(answer(click)) === nothing
    end

    @testset "a link to a file beside the page answers the open of that file with a navigator" begin
        folder = mktempdir()
        write(joinpath(folder, "guide.md"), "# Guide\n")
        file = MarkdownFile(joinpath(folder, "readme.md"), parse_markdown("Read the [guide](guide.md) first.\n"))
        navigator = Navigator(file)
        editor, backend = platform._nav_editor(navigator)
        click = platform._nav_click(backend, "guide")
        @test click !== nothing
        answer = read_intent(editor.projection, nothing, Intent(click), editor.iomap).operation
        opened = answer isa OpenFileOperation ? answer :
                 answer isa CompoundOperation ? only(o for o in answer.operations if o isa OpenFileOperation) : nothing
        @test opened isa OpenFileOperation && opened.path == joinpath(folder, "guide.md")
        @test opened.file_wrap(file) isa Navigator
    end

    @testset "the tooltip of a link shows its target" begin
        root = parse_markdown(_MARKDOWN_LINK_SOURCE)
        link = only(child for child in root.elements[2].content if child isa MarkdownLink)
        opened = get_wrapped_operation(read_gesture(link, MouseDwell(0, 0; time = 0.0)))
        (_, content) = only(opened.layers)
        @test content isa PrimitiveString && content.value == "#install-it"
    end
end
end
