# Fragment of `ShellModule` — the chrome of a window, as a wrapper of
# `build_editor`.

"""
    shell = true | (; assistant, explorer, about, status_bar, measure, appearance)

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
`frame_statistics` ([`RECORDED_TOOLS`](@ref)). In the same way, the Help menu
offers the gesture help and the command palette only when `gesture_help` and
`command_palette` are on. The argument holds the choices of
the host:

- `assistant` makes the assistant of the window from the editor; with
  `nothing`, the default, the toolbar has no assistant, which needs a model.
- `explorer` makes the file explorer of the window from the editor; with
  `nothing` it lists the working directory.
- `about` makes the About page of the Help menu; the default is the page of
  ProjecturEd.
- `status_bar = false` leaves out the status bar.
- `measure` measures the text of the bands, `FontFileMeasure()` by default.
- `appearance` gives the widget theme of the bands; the default is the
  `Appearance` of the `appearance` wrapper of the same editor.
- `tools` adds buttons at the end of the toolbar, such as the button of a tool
  that this package does not name; `make_mcp_log_tool()` is one.

A root that is a shell already keeps its bands.
"""
function wrap_editor!(::Val{:shell}, layer::Symbol, argument, parts::EditorParts)
    parts.document isa WidgetShell && return parts
    options = argument === true ? (;) : argument
    measure = get(options, :measure, FontFileMeasure())
    appearance = get(options, :appearance, get(parts.arguments, :appearance, Appearance()))
    recorded = Tuple(keyword for keyword in RECORDED_TOOLS if haskey(parts.arguments, keyword))
    about = get(options, :about, nothing)
    document = parts.document
    # The Help menu offers a tool of a wrapper only when that wrapper is on.
    gesture_help = haskey(parts.arguments, :gesture_help)
    command_palette = haskey(parts.arguments, :command_palette)
    parts.document = make_window_shell_document(document;
        menu_bar = about === nothing ?
            make_window_menu_bar(; recorded, gesture_help, command_palette) :
            make_window_menu_bar(; recorded, about, gesture_help, command_palette),
        toolbar = make_window_toolbar(; assistant = get(options, :assistant, nothing),
                                        explorer = get(options, :explorer, nothing), recorded,
                                        extra = collect(Any, get(options, :tools, ()))),
        status_bar = get(options, :status_bar, true) ? make_window_status_bar(document) : nothing)
    parts.projection = make_window_shell_projection(parts.projection; measure, appearance)
    append!(parts.opened_window_projections,
            make_opened_window_projections(; gesture_help = false, measure, appearance))
    parts
end

get_wrapper_layers(::Val{:shell}) = (:container => 10,)

"""
    make_opened_window_projections(; gesture_help = true, content = [],
                                   measure::TextMeasure = FontFileMeasure(),
                                   appearance::Appearance = Appearance()) -> Vector

What draws the content of a window that opens later: the rows of the
`opened_window_projections` of a window scene.

**A window whose content type is named by no row draws nothing.** The help
window of F1 holds a `GestureMap`, which this function names when
`gesture_help` is on. A tooltip window holds a `TooltipContent`, which the
natural projection draws, so **a host that shows tooltips passes the natural
rows** as `content`, with the rows that draw its own documents. They are the
rows the window already draws a pane's content with.

**A popup holds widgets**: the menu of a menu bar or of a context menu, and the
options of a `WidgetSelect`, in a layout. So the rows end with the rows of
`WidgetToGraphics`, one for each widget and each layout, in the scaled widget
theme of `appearance` and the measure the shell draws its bands with. The rows
of `content` come before them, so a host decides first. The `shell` wrapper adds
the rows of the widgets to its editor with this function.
"""
make_opened_window_projections(; gesture_help::Bool = true,
                                 content = Pair{Type,Any}[],
                                 measure::TextMeasure = FontFileMeasure(),
                                 appearance::Appearance = Appearance()) =
    vcat(gesture_help ?
             Pair{Type,Any}[GestureMap => make_gesture_map_projection(measure;
                 theme = get_scaled_theme!(appearance, GestureHelpTheme),
                 syntax_theme = get_scaled_theme!(appearance, SyntaxTheme),
                 text_theme = get_scaled_theme!(appearance, TextTheme))] :
             Pair{Type,Any}[],
         Pair{Type,Any}[content...],
         Pair{Type,Any}[WidgetToGraphics(; measure = measure,
                                         theme = get_scaled_theme!(appearance, WidgetTheme),
                                         graphics_theme = get_scaled_theme!(appearance, GraphicsTheme)).dispatch...])
