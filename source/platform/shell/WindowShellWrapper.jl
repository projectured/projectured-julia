# Fragment of `ShellModule` — the chrome of a window, as a wrapper of
# `build_editor`.

"""
    shell = true | (; assistant, explorer, about, status_bar, measure)

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

The bands offer a tool that shows what the window records only when the wrapper
that fills it is on: `message_log`, `gesture_log`, `fault_log` and
`frame_statistics` ([`RECORDED_TOOLS`](@ref)). The setting holds the choices of
the host:

- `assistant` makes the assistant of the window from the editor; with
  `nothing`, the default, the toolbar has no assistant, which needs a model.
- `explorer` makes the file explorer of the window from the editor; with
  `nothing` it lists the working directory.
- `about` makes the About page of the Help menu; the default is the page of
  ProjecturEd.
- `status_bar = false` leaves out the status bar.
- `measure` measures the text of the bands, `FontFileMeasure()` by default.

A root that is a shell already keeps its bands.
"""
# @positional: the arity of the wrapper seam of the kernel.
function wrap_editor!(::Val{:shell}, layer::Symbol, setting, parts::EditorParts)
    parts.document isa WidgetShell && return parts
    options = setting === true ? (;) : setting
    measure = get(options, :measure, FontFileMeasure())
    appearance = get(parts.settings, :appearance, Appearance())
    recorded = Tuple(keyword for keyword in RECORDED_TOOLS if haskey(parts.settings, keyword))
    about = get(options, :about, nothing)
    document = parts.document
    parts.document = make_window_shell_document(document;
        menu_bar = about === nothing ? make_window_menu_bar(; recorded) :
                                       make_window_menu_bar(; recorded, about),
        toolbar = make_window_toolbar(; assistant = get(options, :assistant, nothing),
                                        explorer = get(options, :explorer, nothing), recorded),
        status_bar = get(options, :status_bar, true) ? make_window_status_bar(document) : nothing)
    parts.projection = make_window_shell_projection(parts.projection; measure, appearance)
    append!(parts.opened_window_projections,
            make_opened_window_projections(; gesture_help = false, measure, appearance))
    parts
end

get_wrapper_layers(::Val{:shell}) = (:container => 10,)
