# Fragment of `ShellModule` — the chrome of a window, as a wrapper of
# `build_editor`.

"""
    shell = true | (; recorded, measure)

The wrapper of `build_editor` that puts the root document in the chrome of a
window: a `WidgetShell` whose bands are the menu bar of
[`make_window_menu_bar`](@ref), the toolbar of [`make_window_toolbar`](@ref) and
the status bar of [`make_window_status_bar`](@ref), drawn with
[`make_window_shell_projection`](@ref). It is off by default.

It sits around the tabs and inside the window, so a command of a band finds the
pane tree in its content, and the status bar follows the focused tab. The bands
draw with the widget theme of the `appearance` wrapper of the same editor, so the
keys of the zoom and of the scales reach them too. The windows that open later
get the rows that draw the menus of the bar.

- `recorded` says whether the window records what the tools of the session
  show: the message log, the gesture log, the fault log, the statistics and the
  frame times. It goes to the menu bar and to the toolbar. It is `false` by
  default, because this wrapper records nothing, so the bands offer no tool whose
  tab stays empty. The toolbar has no assistant, because an assistant needs a
  model.
- `measure` measures the text of the bands, `FontFileMeasure()` by default.

A root that is a shell already keeps its bands.
"""
# @positional: the arity of the wrapper seam of the kernel.
function wrap_editor!(::Val{:shell}, layer::Symbol, argument, parts::EditorParts)
    parts.document isa WidgetShell && return parts
    options = argument === true ? (;) : argument
    recorded = get(options, :recorded, false)
    measure = get(options, :measure, FontFileMeasure())
    appearance = get(parts.arguments, :appearance, Appearance())
    document = parts.document
    parts.document = make_window_shell_document(document;
                                                menu_bar = make_window_menu_bar(; recorded),
                                                toolbar = make_window_toolbar(; recorded),
                                                status_bar = make_window_status_bar(document))
    parts.projection = make_window_shell_projection(parts.projection; measure, appearance)
    append!(parts.opened_window_projections,
            make_opened_window_projections(; gesture_help = false, measure, appearance))
    parts
end

get_wrapper_layers(::Val{:shell}) = (:container => 10,)
