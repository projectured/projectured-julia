# The tabs of the pane package: `build_editor` puts the root document in the one
# tab of a pane tree, each tab's content draws with the caller's projection
# whatever its type, and `show_document!` opens a later document in a tab, or in
# a window of its own when there are no tabs.

import ProjecturedKernel.BackendModule: Backend, initialize_backend!, quit_backend!,
                                        take_from_devices!, write_to_devices!
import ProjecturedKernel.EditorModule: build_editor
import ProjecturedKernel.DeviceModule: Device
import ProjecturedKernel.ProjectionModule: Projection
import ProjecturedPlatform.ProjectionAlgebraModule: RecursiveProjection,
                                                     TypeDispatchingProjection
import ProjecturedPlatform.ScreenModule: ScreenDocument, show_document!
import ProjecturedPlatform.PaneModule: PaneTree, PaneGroup, PaneTab, get_pane_groups,
                                   make_tabs_projection
import ProjecturedPlatform.WidgetModule: WidgetLabel
import ProjecturedPlatform.NaturalModule: NaturalToGraphics
import ProjecturedPlatform.StyleModule: FontFileMeasure
import ProjecturedPlatform.GraphicsModule: GraphicsCanvas, GraphicsViewport
import ProjecturedKernel.IoMapModule: get_iomap_output

# A backend that declares no output, so the window wrapper puts the root in a
# window.
struct TabsProbeBackend <: Backend end
initialize_backend!(::TabsProbeBackend) = nothing
quit_backend!(::TabsProbeBackend) = nothing
take_from_devices!(::TabsProbeBackend, devices) = nothing
write_to_devices!(::TabsProbeBackend, devices, output) = nothing

# The caller's projection: the natural renderer, which counts the documents that
# it is asked to draw.
struct TabsCountingProjection <: Projection
    inner::Any
    count::Base.RefValue{Int}
end
TabsCountingProjection() =
    TabsCountingProjection(NaturalToGraphics(measure = FontFileMeasure()), Ref(0))
ProjecturedKernel.ProjectionModule.print_document(p::TabsCountingProjection, recursion, input,
                                                  ctx) =
    (p.count[] += 1; print_document(p.inner, p.inner, input, ctx))

_count_tabs(editor) = sum(length(group.tabs) for group in get_pane_groups(
    get_wrapped_document(editor.document).windows[1].content))

# A widget prints its children when its output is read, so a test reads it all.
function _read_graphics(node)
    node isa AbstractCell && return _read_graphics(node[])
    node isa GraphicsCanvas && foreach(_read_graphics, node.elements)
    node isa GraphicsViewport && _read_graphics(node.content)
    nothing
end

function test_tabs_wrapper()
@testset "the tabs wrapper" begin
    @testset "the root goes into the one tab, and draws with the caller's projection" begin
        text = PrimitiveString("hi")
        counting = TabsCountingProjection()
        editor = build_editor(text, counting; backend = TabsProbeBackend(),
                              devices = Device[])
        @test get_wrapped_document(editor.document) isa ScreenDocument
        tree = get_wrapped_document(editor.document).windows[1].content
        @test tree isa PaneTree
        groups = get_pane_groups(tree)
        @test length(groups) == 1 && length(groups[1].tabs) == 1
        @test groups[1].tabs[1].content === text
        # The content is not a widget, so it draws with the caller's projection.
        _read_graphics(get_iomap_output(editor.iomap).windows[1].content)
        @test counting.count[] >= 1
    end

    @testset "tabs = false, a pane tree and a screen keep the root" begin
        label = WidgetLabel("hi")
        @test get_wrapped_document(build_editor(label, TabsCountingProjection();
            backend = TabsProbeBackend(), devices = Device[], tabs = false).document
        ).windows[1].content === label
        tree = PaneTree(PaneGroup([PaneTab("own", WidgetLabel("x"))]))
        @test get_wrapped_document(build_editor(tree, make_tabs_projection(TabsCountingProjection());
            backend = TabsProbeBackend(), devices = Device[]).document
        ).windows[1].content === tree
    end

    @testset "show_document! opens a tab, and focuses it when it is shown already" begin
        editor = build_editor(WidgetLabel("hi"), TabsCountingProjection();
                              backend = TabsProbeBackend(), devices = Device[])
        second = WidgetLabel("second")
        show_document!(second; title = "second", editor)
        @test _count_tabs(editor) == 2
        show_document!(second; title = "second", editor)
        @test _count_tabs(editor) == 2
    end

    @testset "with no tabs, show_document! opens a window of its own" begin
        editor = build_editor(WidgetLabel("hi"), TabsCountingProjection();
                              backend = TabsProbeBackend(), devices = Device[], tabs = false)
        second = WidgetLabel("second")
        show_document!(second; title = "second", editor)
        @test length(get_wrapped_document(editor.document).windows) == 2
        @test get_wrapped_document(editor.document).windows[2].content === second
        show_document!(second; title = "second", editor)
        @test length(get_wrapped_document(editor.document).windows) == 2
    end
end
end
