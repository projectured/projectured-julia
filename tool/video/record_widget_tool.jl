# tool/video/record_widget_tool.jl
#
# Run it as: julia --project=environment/all tool/video/record_widget_tool.jl [<output>.mp4]
#
# Screenplay S4: a tool window from widgets.
# The Evaluator button of the toolbar opens the evaluator. The first forms make
# a button and a tool around it, and the tool gets a pane of its own beside the
# evaluator: Alt+click selects the button, Alt+Up the tool around it, Ctrl+N
# notes the tool, Ctrl+\ splits the window, Ctrl+V pastes the same tool there,
# F2 names the pane, and Ctrl+Alt+Left and Down bring the caret back to the
# prompt. Each later form adds a widget and returns nothing, so the tool grows
# in its own pane. Two writes from the evaluator move the slider and the name,
# and three presses of the button count, and the table follows all of it.

using Projectured, ProjecturedExample, ProjecturedSdl, ProjecturedSdlExample, ProjecturedVideo

const OUTPUT = isempty(ARGS) ? joinpath(pwd(), "widget_tool.mp4") : ARGS[1]

# Read off the window at 1280×720 with no assistant pane.
const EVALUATOR_BUTTON = (50, 38)
const BUTTON_IN_ROW = (332, 345)      # the button in the result row of the tool
const BUTTON_IN_PANE = (827, 105)     # the same button in the tool's own pane

_key(key; hold = 0.4, kwargs...) = (event = KeyDown(key, ModifierKeys(; kwargs...)), hold = hold)
_type(text) = make_typein_gestures(text; hold = 0.15, jitter = 0.6)    # the human rhythm, D13
_press(x, y; hold = 0.6, kwargs...) = [(event = MouseMove(x, y, :none, ModifierKeys()), hold = 0.4),
                                       (event = MousePress(:left, x, y, ModifierKeys(; kwargs...)), hold = hold)]

const FIRST_FORMS = [
    "presses = Cell(0)",
    "live(text) = set_cell_function!(WidgetLabel(Point2D(0, 0), \"\"), text)",
    "button = WidgetButton(Point2D(0, 0), Point2D(160, 36), \"Press me\"; action = () -> presses[] += 1)",
    "tool = VerticalLayout(Any[button]; gap = 12)",
]

const LATER_FORMS = [
    "push!(tool.children, live(() -> \"Pressed \$(presses[]) times\")); nothing",
    "slider = WidgetSlider(Point2D(0, 0), 0.3); push!(tool.children, slider); nothing",
    "push!(tool.children, live(() -> \"Slider at \$(round(slider.value; digits = 2))\")); nothing",
    "name = WidgetText(Point2D(0, 0), \"Ada\"); push!(tool.children, name); nothing",
    "push!(tool.children, WidgetTable(Point2D(0, 0), [\"what\", \"value\"], [[\"presses\", live(() -> string(presses[]))], [\"slider\", live(() -> string(round(slider.value; digits = 2)))], [\"name\", live(() -> string(name.content))]])); nothing",
    "slider.value = 0.8; nothing",
    "name.content = \"Ada Lovelace\"; nothing",
]

_hold_of(form) = endswith(form, "; nothing") ? 2.5 : 1.2

function _forms(forms)
    timeline = Any[]
    for form in forms
        append!(timeline, _type(form))
        push!(timeline, _key(:return; hold = _hold_of(form)))
    end
    timeline
end

function make_timeline()
    vcat(
        _press(EVALUATOR_BUTTON...; hold = 1.5),                  # the evaluator opens
        _forms(FIRST_FORMS),
        _press(BUTTON_IN_ROW...; hold = 0.6, alt = true),         # select the button
        [_key(:up; hold = 0.6, alt = true),                       # and the tool around it
         _key(:n; hold = 0.8, ctrl = true),                       # note the tool
         _key(:backslash; hold = 1.0, ctrl = true),               # split the window
         _key(:v; hold = 1.2, ctrl = true),                       # paste the same tool
         _key(:f2; hold = 0.4)],                                  # name the pane
        _type("My tool"),
        [_key(:escape; hold = 0.8),
         _key(:left; hold = 0.8, ctrl = true, alt = true),        # back to the evaluator
         _key(:down; hold = 0.8)],                                # into the fresh prompt
        _forms(LATER_FORMS),
        vcat([_press(BUTTON_IN_PANE...; hold = 1.0) for _ in 1:3]...),  # three presses count
    )
end

function main()
    directory = mktempdir()
    write(joinpath(directory, "notes.json"), "{\"tool\": \"widgets\"}")
    timeline = make_timeline()
    scripted = 1.0 + sum(entry.hold for entry in timeline) + 4.0
    println("entries: ", length(timeline), ", scripted seconds: ", round(scripted; digits = 1))
    println("recorded: ", record_application_video([joinpath(directory, "notes.json")], timeline, OUTPUT;
                                                   width = 1280, height = 720, fps = 30,
                                                   assistant = :none, root = directory,
                                                   initial_hold = 1.0, final_hold = 4.0))
end

main()
