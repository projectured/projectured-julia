"""
    ShellModule

The shell of a window: the chrome that a window has around the document in it.

The wrapper `shell` of `build_editor` puts the root of an editor in the chrome
of a window, with the menu bar, the toolbar and the status bar. The other
features of a window are wrappers of `build_editor` too, each in the slice that
owns it, so a binary names the ones it wants by keyword and two binaries cannot
drift into two lists.

A popup needs no wrapper of its own. A widget answers its popup at a position in
its own frame, each reader on the way up moves the position into its own frame,
and the window opens the popup at its screen position.
[`make_opened_window_projections`](@ref) gives the row that draws the widgets a
popup holds.

The bands the shell draws are built here too. [`make_window_toolbar`](@ref)
holds the tools of the window, one picture each. A tool that shows what the
window records is there only when the wrapper that fills it is on.
"""
module ShellModule

using ..AppearanceModule
using ..CellModule
using ..ClipboardModule
using ..DomainModule
using ..FileFormatModule
using ..FileSystemModule
using ..PaneModule
using ..ScreenModule
using ..DocumentModule
using ..EditorModule
using ..IntentModule
using ..IoMapModule
using ..ProjectionAlgebraModule
using ..ProjectionModule
using ..ReferenceModule
using ..SelectionModule
using ..FocusModule
using ..NaturalModule
using ..GraphicsModule
using ..GestureHelpModule
using ..GestureLogModule
using ..HelpModule
using ..StyleModule
using ..ToolModule
using ..TooltipModule
using ..WidgetModule
using ..AssistantModule
using ..ConversationModule
using ..FaultModule
using ..FaultViewModule
using ..FeedModule
using ..FrameStatisticsModule
using ..InspectorModule
using ..MessageLogModule
using ..SettingsManagingModule
using ..SettingsModule
using ..SyntaxModule
using ..TextModule

# Imported to extend: this module adds a method to each of these.
import ..EditorModule: wrap_editor!, get_wrapper_layers




export make_window_shell_document, make_window_shell_projection
export make_window_menu_bar, make_window_file_menu, make_window_view_menu, make_window_help_menu,
       make_window_toolbar, RECORDED_TOOLS, make_window_status_bar, make_window_command,
       make_window_tool_command
export make_file_dialog, open_file_dialog!, save_file_dialog!
export make_opened_window_projections

include("WindowShell.jl")
include("WindowChrome.jl")
include("FileDialog.jl")
include("WindowShellWrapper.jl")

end # module
