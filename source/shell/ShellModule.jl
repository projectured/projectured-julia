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
using ..DocumentModule
using ..IntentModule
using ..IoMapModule
using ..ProjectionModule
using ..ReferenceModule
using ..FocusModule
using ..GestureHelpModule
using ..GestureLogModule
using ..StyleModule
using ..TooltipModule
using ..WidgetModule

# Imported to extend: this module adds a method to each of these.
import ..ProjectionModule: print_document, read_intent, map_reference_forward, map_reference_backward

export make_window_wrap, make_opened_window_projections, make_popup_screen_wrap
export WindowShellProjection, WindowShellIoMap

include("WindowWrap.jl")
include("WindowShell.jl")

end # module
