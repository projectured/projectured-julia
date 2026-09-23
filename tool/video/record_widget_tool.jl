# tool/video/record_widget_tool.jl
#
# Run it as: julia --project=environment/all tool/video/record_widget_tool.jl [<output>.mp4]
#
# Screenplay S4: a tool window from widgets.
# The evaluator builds the tool, each form adds a widget, and the tool takes a
# tab of its own at the end. With `--clicks`, the pointer then presses the
# button, drags the slider and types in the field.

using Projectured, ProjecturedExample, ProjecturedSdl, ProjecturedSdlExample, ProjecturedVideo

const OUTPUT = isempty(ARGS) ? joinpath(pwd(), "widget_tool.mp4") : ARGS[1]
const WITH_CLICKS = "--clicks" in ARGS

# Where the pointer acts, read off a frame of the build recording.
const BUTTON = (344, 111)
const SLIDER = (336, 184)
const FIELD  = (300, 251)

_key(key; hold = 0.35, kwargs...) = (event = KeyDown(key, ModifierKeys(; kwargs...)), hold = hold)
_type(text) = make_typein_gestures(text; hold = 0.15, jitter = 0.6)    # the human rhythm, D13

const FORMS = [
    "presses = Cell(0)",
    "live(text) = set_cell_function!(WidgetLabel(Point2D(0, 0), \"\"), text)",
    "button = WidgetButton(Point2D(0, 0), Point2D(160, 36), \"Press me\"; action = () -> presses[] += 1)",
    "tool = VerticalLayout(Any[button]; gap = 12)",
    "push!(tool.children, live(() -> \"Pressed \$(presses[]) times\")); tool",
    "slider = WidgetSlider(Point2D(0, 0), 0.3); push!(tool.children, slider); tool",
    "push!(tool.children, live(() -> \"Slider at \$(round(slider.value; digits = 2))\")); tool",
    "name = WidgetText(Point2D(0, 0), \"Ada\"); push!(tool.children, name); tool",
    "push!(tool.children, WidgetTable(Point2D(0, 0), [\"what\", \"value\"], [[\"presses\", live(() -> string(presses[]))], [\"slider\", live(() -> string(round(slider.value; digits = 2)))], [\"name\", live(() -> string(name.content))]])); tool",
    "presses[] = 3; tool",
    "slider.value = 0.8; tool",
    "name.content = \"Ada Lovelace\"; tool",
    "open_pane!(editor, tool; title = \"My tool\")",
]

_hold_of(form) = startswith(form, "push!") || startswith(form, "open_pane!") ||
                 occursin("] = ", form) || occursin(".value = ", form) || occursin(".content = ", form) ? 2.5 : 1.2

function make_timeline()
    timeline = Any[
        _key(:t; hold = 0.6, ctrl = true),
        _key(:insert; hold = 0.4),
        _type("repl")...,
        _key(:return; hold = 1.5),
    ]
    for form in FORMS
        append!(timeline, _type(form))
        push!(timeline, _key(:return; hold = _hold_of(form)))
    end
    WITH_CLICKS || return timeline
    # The pointer: three presses of the button, a drag of the slider, and a
    # word typed into the field.
    for _ in 1:3
        push!(timeline, (event = MousePress(:left, BUTTON[1], BUTTON[2], ModifierKeys()), hold = 0.8))
    end
    push!(timeline, (event = MouseDown(:left, SLIDER[1], SLIDER[2], ModifierKeys()), hold = 0.4))
    for x in range(SLIDER[1], 470; length = 9)
        push!(timeline, (event = MouseMove(round(Int, x), SLIDER[2], :left, ModifierKeys()), hold = 0.12))
    end
    push!(timeline, (event = MouseUp(:left, 470, SLIDER[2], ModifierKeys()), hold = 1.5))
    push!(timeline, (event = MousePress(:left, FIELD[1], FIELD[2], ModifierKeys()), hold = 0.8))
    append!(timeline, _type(" Lovelace"))
    push!(timeline, (event = KeyDown(:return, ModifierKeys()), hold = 2.5))
    timeline
end

function main()
    directory = mktempdir()
    write(joinpath(directory, "notes.json"), "{\"tool\": \"widgets\"}")
    timeline = make_timeline()
    scripted = 1.0 + sum(entry.hold for entry in timeline) + 3.0
    println("entries: ", length(timeline), ", scripted seconds: ", round(scripted; digits = 1))
    println("recorded: ", record_application_video([joinpath(directory, "notes.json")], timeline, OUTPUT;
                                                   width = 1280, height = 720, fps = 30,
                                                   assistant = :none, root = directory,
                                                   initial_hold = 1.0, final_hold = 3.0))
end

main()
