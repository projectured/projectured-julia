# tool/video/record_rotating_vector.jl
#
# Run it as: julia --project=environment/all tool/video/record_rotating_vector.jl [<output>.mp4]
#
# Screenplay S1: the evaluator rebuilds the rotating vector example.
# One video. Each form adds a part, and the picture grows into the example.

using Projectured, ProjecturedExample, ProjecturedSdl, ProjecturedSdlExample, ProjecturedVideo

const OUTPUT = isempty(ARGS) ? joinpath(pwd(), "rotating_vector.mp4") : ARGS[1]

# A directory with one small file, so the window opens with a wide pane that
# holds a file tab. A new tab then opens beside that file and not in the
# narrow column of the navigator.
function make_root()
    root = mktempdir()
    write(joinpath(root, "notes.json"), "{\"example\": \"rotating vector\"}")
    root
end

# The forms the video types, in order. Each one is a single line, so the
# evaluator needs no line break, and each one is a beat of the screenplay.
const FORMS = [
    "clock = get_wall_clock()",
    "canvas = GraphicsCanvas([GraphicsRect(0, 0, 300, 300, color_solarized_background_lighter)]; w = 300, h = 300)",
    "ring = GraphicsCircle(90, 90, 60, StyleColor(0.0, 0.0, 0.0, 0.0); border_width = 2, border_color = color_solarized_content_darker)",
    "push!(canvas.elements, ring); canvas",
    "phase() = -0.5 * get_reactive_clock_time(clock)",
    "dot = GraphicsCircle(ComputedCell(() -> round(Int32, 90 + 60cos(phase()))), ComputedCell(() -> round(Int32, 90 - 60sin(phase()))), 5, color_solarized_magenta, 0, StyleColor(0.0, 0.0, 0.0, 0.0), nothing)",
    "push!(canvas.elements, dot); canvas",
    "sine = GraphicsPolyline(ComputedCell(() -> Tuple{Int,Int}[(170 + i, round(Int, 90 - 60sin(phase() - i * 0.02))) for i in 0:120]), color_solarized_blue, 2, nothing, false, false, 8, nothing)",
    "push!(canvas.elements, sine); canvas",
    "cosine = GraphicsPolyline(ComputedCell(() -> Tuple{Int,Int}[(round(Int, 90 + 60cos(phase() - i * 0.02)), 170 + i) for i in 0:120]), color_solarized_green, 2, nothing, false, false, 8, nothing)",
    "push!(canvas.elements, cosine); canvas",
    "push!(canvas.elements, GraphicsLine(170, ComputedCell(() -> dot.cy), ComputedCell(() -> dot.cx), ComputedCell(() -> dot.cy), color_solarized_content_lighter, 1, (5, 5), nothing)); canvas",
    "push!(canvas.elements, GraphicsLine(ComputedCell(() -> dot.cx), 170, ComputedCell(() -> dot.cx), ComputedCell(() -> dot.cy), color_solarized_content_lighter, 1, (5, 5), nothing)); canvas",
]

# How long the picture stays on the screen after a form runs. A form that
# changes the picture holds longer, so the viewer sees what it added.
_hold_of(form) = startswith(form, "push!") ? 3.0 : 1.2

function make_timeline()
    timeline = Any[
        # Ctrl+T opens a tab, Insert starts the name buffer, "repl" names the
        # tool, and Enter commits it.
        (event = KeyDown(:t, ModifierKeys(ctrl = true)), hold = 0.6),
        (event = KeyDown(:insert, ModifierKeys()),       hold = 0.4),
        make_typein_gestures("repl"; hold = 0.12, jitter = 0.4)...,
        (event = KeyDown(:return, ModifierKeys()),       hold = 1.5),
    ]
    for form in FORMS
        append!(timeline, make_typein_gestures(form; hold = 0.045, jitter = 0.5))
        push!(timeline, (event = KeyDown(:return, ModifierKeys()), hold = _hold_of(form)))
    end
    timeline
end

function main()
    root = make_root()
    timeline = make_timeline()
    scripted = 0.5 + sum(entry.hold for entry in timeline) + 4.0
    println("entries: ", length(timeline), ", scripted seconds: ", round(scripted; digits = 1))
    path = record_application_video([joinpath(root, "notes.json")], timeline, OUTPUT;
                                    width = 1280, height = 720, fps = 30,
                                    assistant = :none, root = root,
                                    initial_hold = 0.5, final_hold = 4.0)
    println("recorded: ", path)
end

main()
