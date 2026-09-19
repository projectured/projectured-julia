"""
    ProjecturedShell

The shell of a window: the fold that stacks its wrappers, and the wrap that puts
the popup resolver on the window route.

The submodules below are aliased so this package's source files keep their
relative `..XxxModule` references.
"""
module ProjecturedShell

using ProjecturedClipboard
using ProjecturedFocus
using ProjecturedGestureHelp
using ProjecturedGestureLog
using ProjecturedKernel
using ProjecturedScreen
using ProjecturedStyle
using ProjecturedTooltip
using ProjecturedWidget

const ClipboardModule = ProjecturedClipboard.ClipboardModule
const FocusModule = ProjecturedFocus.FocusModule
const GestureHelpModule = ProjecturedGestureHelp.GestureHelpModule
const GestureLogModule = ProjecturedGestureLog.GestureLogModule
const StyleModule = ProjecturedStyle.StyleModule
const TooltipModule = ProjecturedTooltip.TooltipModule
const WidgetModule = ProjecturedWidget.WidgetModule

include("../../../source/shell/ShellModule.jl")

end # module ProjecturedShell
