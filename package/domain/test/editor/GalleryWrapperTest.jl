# Tests for the layered gallery wrappers — the `dragging`, `shell`, `hover`,
# `gesture_help` and `command_palette` flags of `run_example`. `run_example`
# itself opens a window, so each test drives the helper pair the flag applies and
# the scene assembly the flags feed. What the flags do to the reader is covered
# elsewhere (DraggingTest, GestureHelpTest, HoverProbeTest); what these tests
# prove is that a wrapped example still renders and that a seeded selection still
# reaches the screen through the wrappers.

using Test
using ProjecturedDomainExample: make_dragging_document, make_dragging_projection,
                          make_shell_document, make_shell_projection,
                          make_command_palette_projection,
                          _build_window_scene
using ProjecturedKernel.ReferenceModule: try_evaluate_reference

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

    @testset "hover tracking leaves the render unchanged" begin
        projection = WidgetHoverTrackingProjection(inner = make_json_projection_example())
        @test _gw_count_texts(_gw_render(projection, make_json_document_example())) == bare
    end

    @testset "the command type-in overlay reports that it is not implemented" begin
        @test_throws ErrorException make_command_palette_projection(
            make_json_projection_example())
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
end
end
