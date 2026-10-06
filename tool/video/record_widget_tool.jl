# tool/video/record_widget_tool.jl
#
# Run it as: julia --project=environment/all tool/video/record_widget_tool.jl [<output>.mp4] [probe]
#
# Screenplay S4: a tool window from widgets.
# The Evaluator button of the toolbar opens the evaluator. The first forms make
# a button and a tool around it, and the tool gets a pane of its own beside the
# evaluator: Alt+click selects the button, Alt+Up the tool around it, Ctrl+N
# notes the tool, Ctrl+\ splits the window, Ctrl+V pastes the same tool there,
# F2 names the pane, and Ctrl+Alt+Left and Down bring the caret back to the
# prompt. A helper, `add!`, adds widgets to the tool and returns nothing, so the
# tool grows in its own pane and no result row changes with it. Each widget is
# shown at work when it is added: three presses of the button after the label
# that counts them, a drag of the slider after the label that reads it, and at
# the end one more press and one more drag, which the table follows. Each press
# is a real mouse down and up, and the video draws the pointer.
#
# Before the take, the first steps run once, typed fast, into a take that is
# thrown away, so the evaluator, the split, a click and a drag are compiled
# before the first frame. A first click that waits for compilation is lost: the
# gesture recognizer counts a click only when the up comes within 0.3 s.
#
# With `probe` as the second argument the script records only a fast take in
# video time, and prints the second at which each moment of it starts.

using ProjecturedAll, ProjecturedExample, ProjecturedSDL, ProjecturedSDLExample, ProjecturedVideo

const OUTPUT = isempty(ARGS) ? joinpath(pwd(), "widget_tool.mp4") : ARGS[1]
const PROBE = get(ARGS, 2, "") == "probe"

# Read off the window at 1280×720 with no assistant pane.
const EVALUATOR_BUTTON = (50, 38)
const BUTTON_IN_ROW = (336, 295)      # the button in the result row of the tool
const BUTTON_IN_PANE = (831, 123)     # the same button in the tool's own pane
const SLIDER_TRACK = (777, 198, 240)  # the left end, the height and the width of its track

include(joinpath(@__DIR__, "julia_forms.jl"))
include(joinpath(@__DIR__, "s4_forms.jl"))

_key(key; hold = 0.4, kwargs...) = (event = KeyDown(key, ModifierKeys(; kwargs...);
                                                    time = time()), hold = hold)
_type(text) = make_typein_gestures(text; hold = 0.06, jitter = 0.5)    # a fast typist
_type_fast(text) = [(event = KeyPress(c; time = time()), hold = 0.01) for c in text]
_type_by_frame(text) = [(event = KeyPress(c;
                                          time = time()), hold = 1 / 30) for c in text]    # one key a frame
_press(x, y; hold = 0.6, kwargs...) = [(event = MouseMove(x, y, MouseButtons(), ModifierKeys();
                                                          time = time()), hold = 0.4),
                                       (event = MouseDown(:left, x, y, ModifierKeys(; kwargs...);
                                                          time = time()), hold = 0.1),
                                       (event = MouseUp(:left, x, y, ModifierKeys(; kwargs...);
                                                        time = time()), hold = hold)]

# A drag of the slider's knob from one value to another, 4 px a frame.
function _drag_slider(from, to; hold = 1.5)
    left, y, width = SLIDER_TRACK
    x0, x1 = round(Int, left + from * width), round(Int, left + to * width)
    step = x1 >= x0 ? 4 : -4
    vcat([(event = MouseMove(x0, y, MouseButtons(), ModifierKeys();
                             time = time()), hold = 0.5),
          (event = MouseDown(:left, x0, y, ModifierKeys(); time = time()), hold = 0.3)],
         [(event = MouseMove(x, y, MouseButtons(:left), ModifierKeys();
                             time = time()), hold = 1 / 30) for x in x0 + step:step:x1],
         [(event = MouseUp(:left, x1, y, ModifierKeys(); time = time()), hold = hold)])
end

# How long the window stays still after a form runs. A form that changes the
# tool holds longer, so the viewer sees what it added.
_hold_of(form) = startswith(form, "add!(") && !occursin(" = foreach", form) ? 2.0 : 1.2

function _forms(forms; type = _type)
    timeline = Any[]
    for form in forms
        append!(timeline, type(form))
        push!(timeline, _key(:return; hold = _hold_of(form)))
    end
    timeline
end

# From the tool's pane, where F2 named it, back to the prompt of the evaluator.
_back_to_prompt() = [_key(:left; hold = 0.8, ctrl = true, alt = true), _key(:down; hold = 0.8)]

# The moments of the take, each a name and its entries.
function make_moments(; type = _type)
    [
        "the evaluator opens" => _press(EVALUATOR_BUTTON...; hold = 1.5),
        "the tool" => _forms(TOOL_FORMS; type),
        "the tool gets a pane" => vcat(
            _press(BUTTON_IN_ROW...; hold = 0.8, alt = true),    # select the button
            [_key(:up; hold = 0.6, alt = true),                  # and the tool around it
             _key(:n; hold = 0.8, ctrl = true),                  # note it
             _key(:backslash; hold = 1.0, ctrl = true),          # split the window
             _key(:v; hold = 1.2, ctrl = true),                  # paste the same tool
             _key(:f2; hold = 0.4)],                             # name the pane
            type("My tool"),
            [_key(:escape; hold = 0.8)],
            _back_to_prompt()),
        "the counter" => _forms(COUNTER_FORMS; type),
        # A press or a drag in the tool's pane leaves the focus and the caret in
        # the evaluator, so the next form is typed at once.
        "three presses" => vcat([_press(BUTTON_IN_PANE...; hold = 0.8) for _ in 1:3]...),
        "the slider" => _forms(SLIDER_FORMS; type),
        "a drag" => _drag_slider(0.3, 0.8),
        "the table" => _forms(TABLE_FORMS; type),
        "the table follows" => vcat(_press(BUTTON_IN_PANE...; hold = 1.0), _drag_slider(0.8, 0.55; hold = 2.0)),
    ]
end

make_timeline(; kwargs...) = vcat(last.(make_moments(; kwargs...))...)

# The warm-up: the first half, typed fast, then a press and a drag.
function make_warm_up_timeline()
    moments = Dict(make_moments(; type = _type_fast))
    vcat(moments["the evaluator opens"], moments["the tool"], moments["the tool gets a pane"],
         moments["the counter"], moments["three presses"], moments["the slider"], _drag_slider(0.3, 0.5; hold = 0.3))
end

# The Files pane lists the example project of the repository, and its README is
# open, so the window has a wide pane of files and the Evaluator button opens its
# tab there. The take reads the project and writes nothing into it.
const PROJECT = normpath(joinpath(@__DIR__, "..", "..", "example", "platform", "filesystem", "fixture",
                                   "project"))

function _record(timeline, output; kwargs...)
    record_application_video([joinpath(PROJECT, "README.md")], timeline, output;
                             width = 1280, height = 720, fps = 30, assistant = :none, root = PROJECT, kwargs...)
end

function main()
    check_julia_forms(S4_FORMS)
    if PROBE
        # One key a frame and video time: each moment starts at a second that
        # the schedule alone decides.
        moments = make_moments(; type = _type_by_frame)
        second = 0.5
        for (name, entries) in moments
            println(rpad(name, 22), round(second; digits = 2))
            second += sum(entry.hold for entry in entries)
        end
        println("recorded: ", _record(vcat(last.(moments)...), OUTPUT; initial_hold = 0.5, final_hold = 1.0,
                                      video_time = true))
        return
    end
    warm_up = joinpath(dirname(OUTPUT), "widget_tool_warm_up.mp4")
    println("warm-up: ", _record(make_warm_up_timeline(), warm_up; initial_hold = 0.2, final_hold = 0.2))
    rm(warm_up; force = true)
    timeline = make_timeline()
    scripted = 1.0 + sum(entry.hold for entry in timeline) + 4.0
    println("entries: ", length(timeline), ", scripted seconds: ", round(scripted; digits = 1))
    println("recorded: ", _record(timeline, OUTPUT; initial_hold = 1.0, final_hold = 4.0))
end

main()
