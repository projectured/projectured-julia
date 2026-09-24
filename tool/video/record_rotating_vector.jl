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
# helper, `draw!`, adds elements to the canvas and returns nothing, so each later
# form adds one part, the picture grows in its own pane, and no result row changes
# with it. A moving part takes a function where it moves, and the axes of the two
# traces come last. Every form becomes a Julia document.
#
# Before the take, the first steps run once, typed fast, into a take that is
# thrown away, so the evaluator and the split are compiled before the first frame.

using Projectured, ProjecturedExample, ProjecturedSdl, ProjecturedSdlExample, ProjecturedVideo

const OUTPUT = isempty(ARGS) ? joinpath(pwd(), "rotating_vector.mp4") : ARGS[1]

# Read off the window at 1280×720 with no assistant pane.
const EVALUATOR_BUTTON = (50, 38)
const CANVAS_CENTRE = (432, 362)      # the canvas row after the first two forms

# The navigator lists the example project of the repository, and its README is
# open, so the window has a wide pane of files and the Evaluator button opens its
# tab there. The take reads the project and writes nothing into it.
const PROJECT = normpath(joinpath(@__DIR__, "..", "..", "example", "filesystem", "fixture", "project"))

_key(key; hold = 0.4, kwargs...) = (event = KeyDown(key, ModifierKeys(; kwargs...)), hold = hold)
_type(text) = make_typein_gestures(text; hold = 0.15, jitter = 0.6)    # the human rhythm, D13
_press(x, y; hold = 0.6, kwargs...) = [(event = MouseMove(x, y, :none, ModifierKeys()), hold = 0.4),
                                       (event = MousePress(:left, x, y, ModifierKeys(; kwargs...)), hold = hold)]

# The forms before the canvas has a pane of its own.
const FIRST_FORMS = [
    "clock = get_wall_clock()",
    "canvas = GraphicsCanvas([GraphicsRect(0, 0, 300, 300; color = color_solarized_background_lighter)]; w = 300, h = 300)",
]

# The forms after it. Each `draw!` returns nothing, so its result row says
# `nothing`, and the picture changes only where it is: in its pane, and in the one
# row that made it.
const LATER_FORMS = [
    "draw!(elements...) = foreach(element -> push!(canvas.elements, element), elements)",
    "draw!(GraphicsCircle(90, 90, 60; color = color_transparent, border_width = 2, border_color = color_solarized_content_darker))",
    "phase() = -0.5 * get_reactive_clock_time(clock)",
    "dot = GraphicsCircle(() -> 90 + 60 * cos(phase()), () -> 90 - 60 * sin(phase()), 5; color = color_solarized_magenta)",
    "draw!(dot)",
    "draw!(GraphicsPolyline(() -> [(170 + i, 90 - 60 * sin(phase() - i / 50)) for i in 0:120]; color = color_solarized_blue, width = 2))",
    "draw!(GraphicsPolyline(() -> [(90 + 60 * cos(phase() - i / 50), 170 + i) for i in 0:120]; color = color_solarized_green, width = 2))",
    "draw!(GraphicsLine(170, () -> dot.cy, () -> dot.cx, () -> dot.cy; color = color_solarized_content_lighter, dash = (5, 5)))",
    "draw!(GraphicsLine(() -> dot.cx, 170, () -> dot.cx, () -> dot.cy; color = color_solarized_content_lighter, dash = (5, 5)))",
    "draw!(GraphicsLine(170, 90, 290, 90), GraphicsLine(170, 30, 170, 150))",
    "draw!(GraphicsLine(90, 170, 90, 290), GraphicsLine(30, 170, 150, 170))",
]

# How long the window stays still after a form runs. A form that changes the
# picture holds longer, so the viewer sees what it added.
_changes_picture(form) = startswith(form, "draw!(") && !occursin(" = foreach", form)
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
_type_fast(text) = [(event = KeyPress(c), hold = 0.01) for c in text]

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
    warm_up = joinpath(dirname(OUTPUT), "rotating_vector_warm_up.mp4")
    println("warm-up: ", record_application_video([joinpath(PROJECT, "README.md")], make_warm_up_timeline(),
                                                  warm_up; width = 1280, height = 720, fps = 30,
                                                  assistant = :none, root = PROJECT,
                                                  initial_hold = 0.2, final_hold = 0.2))
    rm(warm_up; force = true)
    timeline = make_timeline()
    scripted = 0.5 + sum(entry.hold for entry in timeline) + 4.0
    println("entries: ", length(timeline), ", scripted seconds: ", round(scripted; digits = 1))
    path = record_application_video([joinpath(PROJECT, "README.md")], timeline, OUTPUT;
                                    width = 1280, height = 720, fps = 30,
                                    assistant = :none, root = PROJECT,
                                    initial_hold = 1.0, final_hold = 4.0)
    println("recorded: ", path)
end

main()
