"""
    ShellModule

The shell of a window: everything a window has besides the document in it.

Two things live here, and a binary uses both.

[`make_window_wrap`](@ref) is the fold `(document, projection) -> (document,
projection)` that stacks the window's wrappers: the gesture help, the command
palette, the gesture log, the selection walk and the clipboard. A binary names
the wrappers it wants by keyword, so two binaries cannot drift into two lists.

[`make_popup_screen_wrap`](@ref) is the other half, and it is not part of the
fold. A popup is a native window, so the operation that opens one carries screen
coordinates, and `WidgetPopupResolverProjection` reaches them only on the window
route. It is the value of the `screen_wrap` keyword of `run_window_editor`.

Without it a `WidgetSelect` does not drop down, a submenu does not open, and a
`WidgetContextMenu` swallows the right press.
"""
module ShellModule

using ..CellModule
using ..ClipboardModule
using ..FileFormatModule
using ..FileSystemModule
using ..PaneModule
using ..ScreenModule
using ..DocumentModule
using ..IntentModule
using ..IoMapModule
using ..ProjectionAlgebraModule
using ..ProjectionModule
using ..ReferenceModule
using ..SelectionModule
using ..FocusModule
using ..GestureHelpModule
using ..GestureLogModule
using ..StyleModule
using ..TooltipModule
using ..WidgetModule




export make_window_wrap, make_opened_window_projections, make_popup_screen_wrap
export make_window_shell_document, make_window_shell_projection
export make_window_menu_bar, make_window_toolbar, make_window_status_bar, make_window_command
export make_file_dialog, open_file_dialog!, save_file_dialog!

include("WindowWrap.jl")
include("WindowShell.jl")
include("WindowChrome.jl")
include("FileDialog.jl")

end # module
