# Fragment of `ShellModule` — the chrome a window is drawn in.
#
# **The shell is a document.** A window's document is wrapped in a `WidgetShell`
# whose `content` holds what the window shows, and the chrome is its menu bar,
# its toolbar, its status bar and its own context menu. This is what a
# projectional editor means by a user interface: the chrome is structured data
# like everything else, so it can be selected, referenced, walked, copied, saved
# and reached by a verb. A shell built inside a printer could be none of those.
#
# It pairs a document wrapper with a projection, as every other wrapper here
# does: `make_clipboard_document` / `make_clipboard_projection`, and now
# `make_window_shell_document` / `make_window_shell_projection`.

"""
    make_window_shell_document(document; menu_bar = nothing, toolbar = nothing,
                               status_bar = nothing, context_menu = nothing,
                               size = nothing) -> WidgetShell

Put `document` in a window's chrome.

A `WidgetShell` **with no size hugs its content**, which a window shell must not
do, so a caller that knows the window's size says it.

Wrapping is idempotent: a document that is already a shell — one read back from a
saved user interface — keeps its identity and takes the bands it is given, so a
window opened from a file is not wrapped twice.
"""
function make_window_shell_document(document; menu_bar = nothing, toolbar = nothing,
                                    status_bar = nothing, context_menu = nothing,
                                    size = nothing)
    document isa WidgetShell || return WidgetShell(document; menu_bar = menu_bar,
                                                             toolbar = toolbar,
                                                             status_bar = status_bar,
                                                             context_menu = context_menu,
                                                             size = size)
    menu_bar === nothing || (document.menu_bar = menu_bar)
    toolbar === nothing || (document.toolbar = toolbar)
    status_bar === nothing || (document.status_bar = status_bar)
    context_menu === nothing || (document.context_menu = context_menu)
    size === nothing || (document.size = size)
    document
end

"""
    make_window_shell_projection(projection; measure = measure_truetype_text,
                                 font = font_ubuntu_regular_20) -> Projection

How a window inside its chrome is drawn: the shell's own bands are widgets, and
the content slot defers to `projection`, so what the window holds is drawn
exactly as it was before the shell.

Pairs with [`make_window_shell_document`](@ref).
"""
make_window_shell_projection(projection; measure = measure_truetype_text,
                             font = font_ubuntu_regular_20) =
    RecursiveProjection(TypeDispatchingProjection(vcat(
        WidgetToGraphics(font; measure = measure).dispatch,
        Pair{Type,Any}[Any => NestingProjection(projection;
                                                recursion = IdentityProjection())])))
