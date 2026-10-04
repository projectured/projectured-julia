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

A `WidgetShell` with no `size` fills the space its parent offers, and **hugs its
content only where its parent offers none either**. A window's shell is drawn
with no parent context, so it would hug its content instead of filling the
window unless a caller that knows the window's size says it.

Wrapping is idempotent: a document that is already a shell — one read back from a
saved user interface — keeps its identity and takes the bands it is given, so a
window opened from a file is not wrapped twice.

A new shell is the new root, so it holds the selection that `document` holds,
rooted at the shell.
"""
function make_window_shell_document(document; menu_bar = nothing, toolbar = nothing,
                                    status_bar = nothing, context_menu = nothing,
                                    size = nothing)
    if !(document isa WidgetShell)
        shell = WidgetShell(document; menu_bar = menu_bar, toolbar = toolbar,
                            status_bar = status_bar, context_menu = context_menu, size = size)
        inner = get_selection(document)
        inner === nothing || replace_selection!(shell,
            concat_references(ConcreteReference(FieldReferenceStep("content"), EmptyReference()),
                              strip_reference_types(inner)))
        return shell
    end
    menu_bar === nothing || (document.menu_bar = menu_bar)
    toolbar === nothing || (document.toolbar = toolbar)
    status_bar === nothing || (document.status_bar = status_bar)
    context_menu === nothing || (document.context_menu = context_menu)
    size === nothing || (document.size = size)
    document
end

"""
    make_window_shell_projection(projection; measure::TextMeasure = FontFileMeasure(),
                                 appearance::Appearance = Appearance()) -> Projection

How a window inside its chrome is drawn: the shell's own bands are widgets,
drawn with the scaled widget theme of `appearance`, and the content slot defers
to `projection`, so what the window holds is drawn exactly as it was before the
shell.

Pairs with [`make_window_shell_document`](@ref).
"""
make_window_shell_projection(projection; measure::TextMeasure = FontFileMeasure(),
                             appearance::Appearance = Appearance()) =
    RecursiveProjection(TypeDispatchingProjection(vcat(
        WidgetToGraphics(; measure = measure,
                         theme = get_scaled_theme!(appearance, WidgetTheme),
                         graphics_theme = get_scaled_theme!(appearance, GraphicsTheme)).dispatch,
        Pair{Type,Any}[Any => NestingProjection(projection;
                                                recursion = IdentityProjection())])))
