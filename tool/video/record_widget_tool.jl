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
# in its own pane. A write from the evaluator changes the name. Then three
# presses of the button count, and a drag moves the slider from 0.3 to 0.8, and
# the table follows all of it. Each press is a real mouse down and up.
#
# Before the take, the first steps run once, typed fast, into a take that is
# thrown away, so the evaluator, the split, a click and a drag are compiled
# before the first frame. A first click that waits for compilation is lost: the
# gesture recognizer counts a click only when the up comes within 0.3 s.

using Projectured, ProjecturedExample, ProjecturedSdl, ProjecturedSdlExample, ProjecturedVideo

const OUTPUT = isempty(ARGS) ? joinpath(pwd(), "widget_tool.mp4") : ARGS[1]

# Read off the window at 1280×720 with no assistant pane.
const EVALUATOR_BUTTON = (50, 38)
const BUTTON_IN_ROW = (332, 345)      # the button in the result row of the tool
const BUTTON_IN_PANE = (827, 105)     # the same button in the tool's own pane
const SLIDER_TRACK = (777, 184, 240)  # the left end, the height and the width of its track

_key(key; hold = 0.4, kwargs...) = (event = KeyDown(key, ModifierKeys(; kwargs...)), hold = hold)
_type(text) = make_typein_gestures(text; hold = 0.06, jitter = 0.5)    # a fast typist
_press(x, y; hold = 0.6, kwargs...) = [(event = MouseMove(x, y, :none, ModifierKeys()), hold = 0.4),
                                       (event = MouseDown(:left, x, y, ModifierKeys(; kwargs...)), hold = 0.1),
                                       (event = MouseUp(:left, x, y, ModifierKeys(; kwargs...)), hold = hold)]

# A drag of the slider's knob from one value to another, 4 px a frame.
function _drag_slider(from, to; hold = 1.5)
    left, y, width = SLIDER_TRACK
    x0, x1 = round(Int, left + from * width), round(Int, left + to * width)
    vcat([(event = MouseMove(x0, y, :none, ModifierKeys()), hold = 0.5),
          (event = MouseDown(:left, x0, y, ModifierKeys()), hold = 0.3)],
         [(event = MouseMove(x, y, :left, ModifierKeys()), hold = 1 / 30) for x in x0 + 4:4:x1],
         [(event = MouseUp(:left, x1, y, ModifierKeys()), hold = hold)])
end

const FIRST_FORMS = [
    "presses = Cell(0)",
    "live(text) = set_cell_computation!(WidgetLabel(\"\"), text)",
    "button = WidgetButton(Point2D(0, 0), Point2D(160, 36), \"Press me\"; action = () -> presses[] += 1)",
    "tool = VerticalLayout(Any[button]; gap = 12)",
]

const LATER_FORMS = [
    "push!(tool.children, live(() -> \"Pressed \$(presses[]) times\")); nothing",
    "slider = WidgetSlider(0.3); push!(tool.children, slider); nothing",
    "push!(tool.children, live(() -> \"Slider at \$(round(slider.value; digits = 2))\")); nothing",
    "name = WidgetText(\"Ada\"); push!(tool.children, name); nothing",
    "push!(tool.children, WidgetTable([\"what\", \"value\"], [[\"presses\", live(() -> string(presses[]))], [\"slider\", live(() -> string(round(slider.value; digits = 2)))], [\"name\", live(() -> string(name.content))]])); nothing",
    "name.content = \"Ada Lovelace\"; nothing",
]

_hold_of(form) = endswith(form, "; nothing") ? 2.5 : 1.2

function _forms(forms; type = _type)
    timeline = Any[]
    for form in forms
        append!(timeline, type(form))
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
        _drag_slider(0.3, 0.8),                                   # the knob, and the table follows
    )
end

# The warm-up: the steps of the first half, typed fast, then a press and a drag.
_type_fast(text) = [(event = KeyPress(c), hold = 0.01) for c in text]

function make_warm_up_timeline()
    vcat(
        _press(EVALUATOR_BUTTON...; hold = 1.0),
        _forms(FIRST_FORMS; type = _type_fast),
        _press(BUTTON_IN_ROW...; hold = 0.5, alt = true),
        [_key(:up; alt = true), _key(:n; ctrl = true), _key(:backslash; ctrl = true), _key(:v; ctrl = true), _key(:f2)],
        _type_fast("My tool"),
        [_key(:escape), _key(:left; ctrl = true, alt = true), _key(:down)],
        _forms(LATER_FORMS[1:3]; type = _type_fast),
        vcat([_press(BUTTON_IN_PANE...; hold = 0.4) for _ in 1:2]...),
        _drag_slider(0.3, 0.5; hold = 0.3),
    )
end

# The navigator lists the example project of the repository, and its README is
# open, so the window has a wide pane of files and the Evaluator button opens its
# tab there. The take reads the project and writes nothing into it.
const PROJECT = normpath(joinpath(@__DIR__, "..", "..", "example", "filesystem", "fixture", "project"))

function main()
    warm_up = joinpath(dirname(OUTPUT), "widget_tool_warm_up.mp4")
    println("warm-up: ", record_application_video([joinpath(PROJECT, "README.md")], make_warm_up_timeline(),
                                                  warm_up; width = 1280, height = 720, fps = 30,
                                                  assistant = :none, root = PROJECT,
                                                  initial_hold = 0.2, final_hold = 0.2))
    rm(warm_up; force = true)
    timeline = make_timeline()
    scripted = 1.0 + sum(entry.hold for entry in timeline) + 4.0
    println("entries: ", length(timeline), ", scripted seconds: ", round(scripted; digits = 1))
    println("recorded: ", record_application_video([joinpath(PROJECT, "README.md")], timeline, OUTPUT;
                                                   width = 1280, height = 720, fps = 30,
                                                   assistant = :none, root = PROJECT,
                                                   initial_hold = 1.0, final_hold = 4.0))
end

main()
