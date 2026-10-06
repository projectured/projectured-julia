# tool/video/record_rotating_vector.jl
#
# Run it as: julia --project=environment/all tool/video/record_rotating_vector.jl [<output>.mp4]
#
# Screenplay S1: the evaluator rebuilds the rotating vector example.
# The Evaluator button of the toolbar opens the evaluator. The first forms make
# a canvas, and the canvas gets a pane of its own beside the evaluator: Alt+click
# selects the canvas, Ctrl+N notes it, Ctrl+\ splits the window, Ctrl+V pastes
# the same canvas there, F2 names the pane, Ctrl+Alt+Left brings the focus back,
# and Down moves the caret from the selected canvas into the fresh prompt. A
# helper, `add!`, adds elements to the canvas and returns nothing, so each later
# form adds one part, the picture grows in its own pane, and no result row changes
# with it. A moving part takes a function where it moves, and the axes of the two
# traces come last. Every form becomes a Julia document.
#
# Before the take, the first steps run once, typed fast, into a take that is
# thrown away, so the evaluator and the split are compiled before the first frame.
#
# The take keeps video time: the animation reads the editor's clock, and each
# frame is 1/30 s after the one before, also while a key makes a frame slow.

using ProjecturedAll, ProjecturedExample, ProjecturedSDL, ProjecturedSDLExample, ProjecturedVideo

const OUTPUT = isempty(ARGS) ? joinpath(pwd(), "rotating_vector.mp4") : ARGS[1]

# Read off the window at 1280×720 with no assistant pane.
const EVALUATOR_BUTTON = (50, 38)
const CANVAS_CENTRE = (432, 362)      # the canvas row after the first two forms

# The Files pane lists the example project of the repository, and its README is
# open, so the window has a wide pane of files and the Evaluator button opens its
# tab there. The take reads the project and writes nothing into it.
const PROJECT = normpath(joinpath(@__DIR__, "..", "..", "example", "platform", "filesystem", "fixture",
                                   "project"))

_key(key; hold = 0.4, kwargs...) = (event = KeyDown(key, ModifierKeys(; kwargs...);
                                                    time = time()), hold = hold)
_type(text) = make_typein_gestures(text; hold = 0.06, jitter = 0.5)    # a fast typist
_press(x, y; hold = 0.6, kwargs...) = [(event = MouseMove(x, y, MouseButtons(), ModifierKeys();
                                                          time = time()), hold = 0.4),
                                       (event = MouseClick(:left, x, y, ModifierKeys(; kwargs...);
                                                           time = time()), hold = hold)]

include(joinpath(@__DIR__, "julia_forms.jl"))
include(joinpath(@__DIR__, "s1_forms.jl"))

# How long the window stays still after a form runs. A form that changes the
# picture holds longer, so the viewer sees what it added.
_changes_picture(form) = startswith(form, "add!(") && !occursin(" = foreach", form)
_hold_of(form) = _changes_picture(form) ? 3.0 : 1.2

function _forms(forms; type = _type)
    timeline = Any[]
    for form in forms
        append!(timeline, type(form))
        push!(timeline, _key(:return; hold = _hold_of(form)))
    end
    timeline
end

# The warm-up: the steps of the first half, typed fast, with no hold to watch.
_type_fast(text) = [(event = KeyPress(c; time = time()), hold = 0.01) for c in text]

function make_warm_up_timeline()
    vcat(
        _press(EVALUATOR_BUTTON...; hold = 1.0),
        _forms(FIRST_FORMS; type = _type_fast),
        _press(CANVAS_CENTRE...; hold = 0.5, alt = true),
        [_key(:n; ctrl = true), _key(:backslash; ctrl = true), _key(:v; ctrl = true), _key(:f2)],
        _type_fast("Picture"),
        [_key(:escape), _key(:left; ctrl = true, alt = true), _key(:down)],
        _forms(LATER_FORMS[1:2]; type = _type_fast),
    )
end

function make_timeline()
    vcat(
        _press(EVALUATOR_BUTTON...; hold = 1.5),                 # the evaluator opens
        _forms(FIRST_FORMS),
        _press(CANVAS_CENTRE...; hold = 0.8, alt = true),        # select the canvas
        [_key(:n; hold = 0.8, ctrl = true),                      # note it
         _key(:backslash; hold = 1.0, ctrl = true),              # split the window
         _key(:v; hold = 1.2, ctrl = true),                      # paste the same canvas
         _key(:f2; hold = 0.4)],                                 # name the pane
        _type("Picture"),
        [_key(:escape; hold = 0.8),
         _key(:left; hold = 1.0, ctrl = true, alt = true),       # back to the evaluator
         _key(:down; hold = 0.8)],                               # from the canvas to the fresh prompt
        _forms(LATER_FORMS),
    )
end

function main()
    check_julia_forms(vcat(FIRST_FORMS, LATER_FORMS))
    warm_up = joinpath(dirname(OUTPUT), "rotating_vector_warm_up.mp4")
    println("warm-up: ", record_application_video([joinpath(PROJECT, "README.md")], make_warm_up_timeline(),
                                                  warm_up; width = 1280, height = 720, fps = 30,
                                                  assistant = :none, root = PROJECT,
                                                  initial_hold = 0.2, final_hold = 0.2,
                                                  video_time = true))
    rm(warm_up; force = true)
    timeline = make_timeline()
    scripted = 1.0 + sum(entry.hold for entry in timeline) + 4.0
    println("entries: ", length(timeline), ", scripted seconds: ", round(scripted; digits = 1))
    path = record_application_video([joinpath(PROJECT, "README.md")], timeline, OUTPUT;
                                    width = 1280, height = 720, fps = 30,
                                    assistant = :none, root = PROJECT,
                                    initial_hold = 1.0, final_hold = 4.0, video_time = true)
    println("recorded: ", path)
end

main()
