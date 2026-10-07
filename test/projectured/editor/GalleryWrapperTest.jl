# Tests for the layered gallery wrappers — the `dragging`, `shell`,
# `gesture_help` and `command_palette` flags of `run_example`. `run_example`
# itself opens a window, so each test drives the helper pair the flag applies and
# the scene assembly the flags feed. What the flags do to the reader is covered
# elsewhere (DraggingTest, GestureHelpTest); what these tests
# prove is that a wrapped example still renders and that a seeded selection still
# reaches the screen through the wrappers.

using Test
using ProjecturedExample: make_dragging_document, make_dragging_projection,
                          make_shell_document, make_shell_projection,
                          make_command_palette_decorator_projection,
                          _build_window_scene, make_example_editor
using ProjecturedKernel.ReferenceModule: try_evaluate_reference
using ProjecturedPlatform.CollectionModule: ListNode

# The number of text leaves a canvas draws. An empty frame counts 0, so this
# separates "renders the content" from "renders a frame around nothing".
function _gw_count_texts(x)
    x isa Cell && return _gw_count_texts(x[])
    if x isa GraphicsCanvas
        n = 0
        for e in x.elements
            n += _gw_count_texts(e)
        end
        return n
    elseif x isa GraphicsViewport
        return _gw_count_texts(x.content)
    elseif x isa GraphicsText
        return 1
    end
    0
end

# Every text a canvas draws, as (x, y, text), through viewports; the rows of a list
# are left out.
function _gw_texts(x, ox = 0, oy = 0, found = Tuple{Int,Int,String}[])
    x isa Cell && return _gw_texts(x[], ox, oy, found)
    if x isa GraphicsCanvas
        elements = x.elements isa Cell ? x.elements[] : x.elements
        elements isa ListNode && return found
        for e in elements
            _gw_texts(e, ox + Int(x.x), oy + Int(x.y), found)
        end
    elseif x isa GraphicsViewport
        _gw_texts(x.content, ox + Int(x.x), oy + Int(x.y), found)
    elseif x isa GraphicsText
        isempty(string(x.text)) || push!(found, (ox + Int(x.x), oy + Int(x.y), string(x.text)))
    end
    found
end

function _gw_render(projection, document)
    output = print_document(projection, document).output
    output isa Cell ? output[] : output
end

function test_gallery_wrappers()
@testset "run_example wrappers" begin
    bare = _gw_count_texts(_gw_render(make_json_projection_example(),
                                      make_json_document_example()))
    @test bare > 0

    @testset "dragging is transparent to the printer" begin
        document   = make_dragging_document(make_json_document_example())
        projection = make_dragging_projection(make_json_projection_example())
        @test document isa DraggingState
        @test _gw_count_texts(_gw_render(projection, document)) == bare
    end

    @testset "a shell frames the content and draws its own chrome" begin
        document   = make_shell_document(make_json_document_example();
                                         title = "json", width = 800, height = 600)
        projection = make_shell_projection(make_json_projection_example())
        @test document isa WidgetShell
        # The content's text plus the chrome's: three menu titles, three toolbar
        # commands, and the two status-bar cells.
        @test _gw_count_texts(_gw_render(projection, document)) == bare + 8
    end

    @testset "the wrappers stack" begin
        document   = make_shell_document(make_dragging_document(make_json_document_example());
                                         title = "json", width = 800, height = 600)
        projection = make_shell_projection(
            make_dragging_projection(make_json_projection_example()))
        @test _gw_count_texts(_gw_render(projection, document)) == bare + 8
    end

    @testset "the command type-in overlay leaves the render unchanged while closed" begin
        projection = make_command_palette_decorator_projection(make_json_projection_example())
        @test projection isa CommandPaletteDecoratorProjection
        # The palette draws nothing until its gesture opens it, so the content
        # renders exactly as it does without the wrapper.
        @test _gw_count_texts(_gw_render(projection, make_json_document_example())) == bare
        # Each call gets its own palette: the overlay is drawn INTO a window, so two
        # windows must not share one open flag.
        other = make_command_palette_decorator_projection(make_json_projection_example())
        @test projection.state !== other.state
    end

    # `_build_window_scene` lifts a seeded selection from the innermost document
    # to a screen-rooted path. `content_unwrap` names the fields the document
    # wrappers introduced, outermost first.
    @testset "the selection lift follows the wrapper fields" begin
        @testset "no wrapper" begin
            document = make_json_document_example()
            set_selection!(document, @reference(document, entries[1].value))
            screen = _build_window_scene(Any[document], String["json"];
                                         width = 800, height = 600)
            @test getfield(screen, :selection)[] !== nothing
        end

        @testset "two wrappers" begin
            inner = make_json_document_example()
            set_selection!(inner, @reference(inner, entries[1].value))
            document = make_shell_document(make_dragging_document(inner);
                                           title = "json", width = 800, height = 600)
            screen = _build_window_scene(Any[document], String["json"];
                                         width = 800, height = 600,
                                         content_unwrap = Symbol[:content, :content])
            lifted = getfield(screen, :selection)[]
            @test lifted !== nothing
            # The path reaches the seeded leaf through both wrappers.
            @test try_evaluate_reference(screen, lifted) ===
                  try_evaluate_reference(inner, getfield(inner, :selection)[])
        end
    end

    @testset "a right click opens a menu that draws in its own window" begin
        # The gallery draws a window that opens later, such as the menu of a
        # right click, through the rows of the widgets.
        example = only(e for e in examples if e.name == "pivot")
        backend = HeadlessBackend()
        editor = make_example_editor(Any[example.make_document()], Any[example.make_projection()],
                                     String["pivot"]; backend, width = 1000, height = 700)
        run_frame!(editor)
        force(value) = value isa Cell ? force(value[]) : value
        windows() = collect(force(force(get_iomap_output(editor.iomap)).windows))
        main = only(windows())
        (x, y) = first((t[1], t[2]) for t in _gw_texts(main.content) if t[3] == "region")
        send!(event) = (push_event!(backend, WindowInput(main.id, event)); run_frame!(editor))
        send!(MouseMove(x + 3, y + 3, MouseButtons(), ModifierKeys(); time = 1.0))
        send!(MouseDown(:right, x + 3, y + 3, ModifierKeys(); time = 1.1))
        send!(MouseUp(:right, x + 3, y + 3, ModifierKeys(); time = 1.15))
        menu = only(window for window in windows() if window.id !== main.id)
        @test "Show the totals" in [t[3] for t in _gw_texts(menu.content)]
    end
end
end
