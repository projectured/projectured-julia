# tool/video/record_rotating_vector.jl
#
# Run it as: julia --project=environment/all tool/video/record_rotating_vector.jl [<output>.mp4]
#
# Screenplay S1: the evaluator rebuilds the rotating vector example.
# The Evaluator button of the toolbar opens the evaluator. The first forms make
# a canvas, and the canvas gets a pane of its own beside the evaluator: Alt+click
# selects the canvas, Ctrl+N notes it, Ctrl+\ splits the window, Ctrl+V pastes
# the same canvas there, F2 names the pane, Ctrl+Alt+Left brings the focus back, and Down moves the
# caret from the selected canvas into the fresh prompt. Each later form adds one part and returns nothing, so
# the picture grows in its own pane and no result row changes with it.

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

# The forms after it. Each `push!` returns nothing, so its result row stays
# small, and the picture changes only where it is: in its pane, and in the one
# row that made it.
const LATER_FORMS = [
    "ring = GraphicsCircle(90, 90, 60; color = StyleColor(0.0, 0.0, 0.0, 0.0), border_width = 2, border_color = color_solarized_content_darker)",
    "push!(canvas.elements, ring); nothing",
    "phase() = -0.5 * get_reactive_clock_time(clock)",
    "dot = GraphicsCircle(ComputedCell(() -> round(Int32, 90 + 60cos(phase()))), ComputedCell(() -> round(Int32, 90 - 60sin(phase()))), 5, color_solarized_magenta, 0, StyleColor(0.0, 0.0, 0.0, 0.0), nothing)",
    "push!(canvas.elements, dot); nothing",
    "sine = GraphicsPolyline(ComputedCell(() -> Tuple{Int,Int}[(170 + i, round(Int, 90 - 60sin(phase() - i * 0.02))) for i in 0:120]), color_solarized_blue, 2, nothing, false, false, 8, nothing)",
    "push!(canvas.elements, sine); nothing",
    "cosine = GraphicsPolyline(ComputedCell(() -> Tuple{Int,Int}[(round(Int, 90 + 60cos(phase() - i * 0.02)), 170 + i) for i in 0:120]), color_solarized_green, 2, nothing, false, false, 8, nothing)",
    "push!(canvas.elements, cosine); nothing",
    "push!(canvas.elements, GraphicsLine(170, ComputedCell(() -> dot.cy), ComputedCell(() -> dot.cx), ComputedCell(() -> dot.cy), color_solarized_content_lighter, 1, (5, 5), nothing)); nothing",
    "push!(canvas.elements, GraphicsLine(ComputedCell(() -> dot.cx), 170, ComputedCell(() -> dot.cx), ComputedCell(() -> dot.cy), color_solarized_content_lighter, 1, (5, 5), nothing)); nothing",
]

# How long the window stays still after a form runs. A form that changes the
# picture holds longer, so the viewer sees what it added.
_hold_of(form) = startswith(form, "push!") ? 3.0 : 1.2

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
