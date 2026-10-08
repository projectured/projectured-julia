"""
    ProjecturedPlatform

The platform: the slices that the domains, the backends and the adapters are
built on. The collections, the primitive values, the projection algebra, the
style, the graphics, the layout, the screen, the text, the syntax and the
natural notation; the widgets, the panes and the window; the clipboard, the
focus and the dragging; the conversation and the assistant; the file system, the
help, the logs, the statistics and the undo; and the application that puts
them in one window. Each slice is a module of its own, in
`source/platform/<slice>/`, and the order of the includes below is an order of
`PLATFORM_SLICE_EDGES`, the table of the edges between the slices.

The loop below binds every submodule of the kernel as a `const`, so a source
file here names a module of the kernel exactly as the module names itself.
"""
module ProjecturedPlatform

using ProjecturedKernel

for _n in names(ProjecturedKernel; all = true)
    isdefined(ProjecturedKernel, _n) || continue
    _m = getfield(ProjecturedKernel, _n)
    (_m isa Module && _m !== ProjecturedKernel && parentmodule(_m) !== Main) || continue
    Core.eval(@__MODULE__, Expr(:const, Expr(:(=), _n, _m)))
end

include("../../../source/platform/collection/CollectionModule.jl")
include("../../../source/platform/component/ComponentModule.jl")
include("../../../source/platform/domain/DomainModule.jl")
include("../../../source/platform/settings/SettingsModule.jl")
include("../../../source/platform/focus/FocusModule.jl")
include("../../../source/platform/dragtracking/DragTrackingModule.jl")
include("../../../source/platform/gesturetracking/GestureTrackingModule.jl")
include("../../../source/platform/primitive/PrimitiveModule.jl")
include("../../../source/platform/projection/ProjectionAlgebraModule.jl")
include("../../../source/platform/dragging/DraggingModule.jl")
include("../../../source/platform/serialization/SerializationModule.jl")
include("../../../source/platform/style/StyleModule.jl")
include("../../../source/platform/graphics/GraphicsModule.jl")
include("../../../source/platform/layout/LayoutModule.jl")
include("../../../source/platform/plot/PlotModule.jl")
include("../../../source/platform/screen/ScreenModule.jl")
include("../../../source/platform/text/TextModule.jl")
include("../../../source/platform/clipboard/ClipboardModule.jl")
include("../../../source/platform/tooltip/TooltipModule.jl")
include("../../../source/platform/versioning/VersioningModule.jl")
include("../../../source/platform/widget/WidgetModule.jl")
include("../../../source/platform/natural/NaturalModule.jl")
include("../../../source/platform/settingsmanaging/SettingsManagingModule.jl")
include("../../../source/platform/conversation/ConversationModule.jl")
include("../../../source/platform/assistant/AssistantModule.jl")
include("../../../source/platform/display/DisplayModule.jl")
include("../../../source/platform/essentials/EssentialsModule.jl")
include("../../../source/platform/inspector/InspectorModule.jl")
include("../../../source/platform/pane/PaneModule.jl")
include("../../../source/platform/reflection/ReflectionModule.jl")
include("../../../source/platform/syntax/SyntaxModule.jl")
include("../../../source/platform/appearance/AppearanceModule.jl")
include("../../../source/platform/fault/FaultViewModule.jl")
include("../../../source/platform/fileformat/FileFormatModule.jl")
include("../../../source/platform/filechange/FileChangeModule.jl")
include("../../../source/platform/undo/UndoModule.jl")
include("../../../source/platform/filesystem/FileSystemModule.jl")
include("../../../source/platform/gesturehelp/GestureHelpModule.jl")
include("../../../source/platform/gesturelog/GestureLogModule.jl")
include("../../../source/platform/help/HelpModule.jl")
include("../../../source/platform/log/MessageLogModule.jl")
include("../../../source/platform/statistics/FrameStatisticsModule.jl")
include("../../../source/platform/shell/ShellModule.jl")
include("../../../source/platform/mcplog/McpLogModule.jl")
include("../../../source/platform/task/TaskModule.jl")
include("../../../source/platform/navigator/NavigatorModule.jl")
include("../../../source/platform/application/ApplicationModule.jl")
include("../../../source/platform/PlatformModule.jl")

# A user who loads the package by name gets every module of it and every name that
# one of them exports.
using .PlatformModule
for _n in names(PlatformModule)
    _n === :PlatformModule || Core.eval(@__MODULE__, Expr(:export, _n))
end

# The rungs of the natural notation that the text gives, and the fallback of the
# syntax.
function __init__()
    NaturalModule.register_natural_rung!(:text, :graphics,
        (; measure, appearance) -> TextModule.TextToGraphics(;
            measure, theme = StyleModule.get_scaled_theme!(appearance, TextModule.TextTheme)))
    NaturalModule.register_natural_rung!(:text, :string,
        (; measure, appearance) -> TextModule.TextToString())
    NaturalModule.register_natural_notation!(
        TextModule.TextDocument, :text,
        (; appearance) -> ProjectionAlgebraModule.IdentityProjection())
    SyntaxModule.register_syntax_fallback!()
    nothing
end

# The display of a value beside the REPL, at the level of the package.
using .DisplayModule
export EditorDisplay, display_in_editor, close_display_editor!, refresh_display_editor!

# The first window of a session, with a backend that has no device, so that this
# image holds the code of the editor, the window and its tools.
using PrecompileTools: @setup_workload, @compile_workload
@setup_workload begin
    @compile_workload begin
        run_display_workload(make_workload_table())
    end
end

end # module ProjecturedPlatform
