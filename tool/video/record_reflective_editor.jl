# tool/video/record_reflective_editor.jl
#
# Run it as: julia --project=environment/all tool/video/record_reflective_editor.jl [<output>.mp4]
#
# Screenplay S7: the editor is reflective. The evaluator walks from `editor` to
# the toolbar and shows it, a press on its copy opens a tool, a form adds a
# button to it, a search finds the explorer, a double-click on its copy opens a
# JSON file, and the document of that file, found by a second search, takes an
# edit in either view. The coordinates are logical pixels of the 1280×720
# window, read off the frames of the rehearsals.
#
# With `PROJECTURED_TAKE_FAST=1` the forms are typed fast, which is the warm-up:
# run it once in the same process before the take, so that no step of the take
# compiles.

using Projectured, ProjecturedKernelExample, ProjecturedSdlExample
using Random

const OUTPUT = isempty(ARGS) ? joinpath(pwd(), "reflective_editor.mp4") : ARGS[1]
const FAST = get(ENV, "PROJECTURED_TAKE_FAST", "") == "1"

const EVALUATOR_BUTTON = (54, 52)       # the toolbar of the window
const GESTURE_LOG_COPY = (399, 541)     # the Gesture log button in the copy of the toolbar
const EVALUATOR_TAB = (437, 94)
const PEOPLE_COPY = (403, 640)          # people.json in the copy of the explorer
const PEOPLE_TAB = (707, 94)            # the tab that the double-click opens
const RIGHT_EDGE = (1240, 400)          # where the tab drops to split the window
const PROMPT = (300, 673)               # the empty form of the evaluator after the split
const BOB_IN_TAB = (938, 260)           # after the "b" of "Bob" in the tab
const ADA_IN_RESULT = (444, 364)        # after the "a" of "Ada" in the result row
const TAB_SPACE = (1000, 500)           # empty space of the JSON tab
const REST = (1262, 400)                # the right margin, off the text

const WINDOW = "editor.document.windows[1]"
const FORMS = (
    screen_type = "nameof(typeof(editor.document))",
    screen_fields = "propertynames(editor.document)",
    window_type = "nameof(typeof($WINDOW))",
    window_fields = "propertynames($WINDOW)",
    shell_type = "nameof(typeof($WINDOW.content.content))",
    shell_fields = "propertynames($WINDOW.content.content)",
    toolbar = "toolbar = $WINDOW.content.content.toolbar",
    button = "push!(toolbar.elements, WidgetToolbarItem(\"Hello\"));",
    files = "files = first(search_documents(editor.document, d -> d isa Workspace))",
    json = "json = first(search_documents(editor.document, d -> d isa JsonFile))",
)

# The folder has a name of its own, because both explorers show it.
function make_demo_folder()
    directory = mkpath(joinpath(mktempdir(), "team"))
    write(joinpath(directory, "README.md"), "# People\n\nThe people of the team, in `people.json`.\n")
    write(joinpath(directory, "people.json"), """
    [
      {"name": "Ada", "age": 36, "city": "London"},
      {"name": "Bob", "age": 41, "city": "Paris"},
      {"name": "Cleo", "age": 29, "city": "Rome"}
    ]
    """)
    directory
end

# ── The gestures, in video time ─────────────────────────────────────────────

mods(; kwargs...) = ModifierKeys(; kwargs...)
key(name; hold = 0.35, kwargs...) = (event = KeyDown(name, mods(; kwargs...); time = 0.0), hold = hold)
pause(seconds) = (await = editor -> false, hold = seconds)
move(x, y; buttons = MouseButtons(), hold = 0.04) =
    (event = MouseMove(x, y, buttons, mods(); time = 0.0), hold = hold)

# The pointer glides from where it is to where it goes next, so the viewer sees
# where a click lands.
const POINTER = Ref((640, 400))
function glide(target; steps = 12, buttons = MouseButtons())
    (x0, y0), (x1, y1) = POINTER[], target
    POINTER[] = target
    [move(round(Int, x0 + (x1 - x0) * t), round(Int, y0 + (y1 - y0) * t); buttons = buttons)
     for t in range(0, 1; length = steps + 1)[2:end]]
end
click(target; hold = 1.0) = Any[glide(target)...,
    (event = MouseClick(:left, target..., 1, mods(); time = 0.0), hold = hold)]
double_click(target; hold = 1.5) = Any[glide(target)..., pause(0.3),
    (event = MouseClick(:left, target..., 1, mods(); time = 0.0), hold = 0.12),
    (event = MouseClick(:left, target..., 2, mods(); time = 0.0), hold = hold)]
function drag(from, to; hold = 1.5)
    out = Any[glide(from)..., pause(0.3),
              (event = MouseDown(:left, from..., mods(); time = 0.0), hold = 0.3)]
    append!(out, glide(to; steps = 20, buttons = MouseButtons(; left = true)))
    push!(out, pause(0.6))
    push!(out, (event = MouseUp(:left, to..., mods(); time = 0.0), hold = hold))
    out
end

# A person types code in short runs: a name, a call up to its `(`, an argument up
# to its `,`, and stops a moment between the runs. The speed is the same for the
# whole take.
const TYPE_HOLD = 0.13
const TYPE_JITTER = 0.4
const RUN_GAP = 0.25

function split_code_runs(code)
    runs = String[]
    current = ""
    for c in code
        current *= c
        if (c in ('(', ',', ' ') && length(current) >= 5) || (c == '.' && length(current) >= 12)
            push!(runs, current)
            current = ""
        end
    end
    isempty(current) || push!(runs, current)
    runs
end

function typed(code)
    FAST && return make_typein_gestures(code; hold = 0.02, jitter = 0.0)
    out = Any[]
    for piece in split_code_runs(code)
        append!(out, make_typein_gestures(piece; hold = TYPE_HOLD, jitter = TYPE_JITTER))
        push!(out, pause(RUN_GAP))
    end
    out
end

# A form is typed and runs on Enter; the hold after it is the time to read what
# it showed.
form(code; hold = 1.8) = Any[typed(code)..., key(:return; hold = hold)]

# ── The screenplay ──────────────────────────────────────────────────────────

function make_timeline()
    POINTER[] = (640, 400)
    Any[
        pause(1.0),
        click(EVALUATOR_BUTTON; hold = 1.5)...,              # 1. the evaluator opens
        glide(REST)...,
        form(FORMS.screen_type)...,                          # 2. `editor` is this window
        form(FORMS.screen_fields; hold = 2.2)...,            # 3. its parts are fields
        form(FORMS.window_type)...,
        form(FORMS.window_fields; hold = 3.0)...,
        form(FORMS.shell_type)...,
        form(FORMS.shell_fields; hold = 3.0)...,
        form(FORMS.toolbar; hold = 2.5)...,                  # 4. the toolbar draws as itself
        click(GESTURE_LOG_COPY; hold = 3.0)...,              # 5. it is the real toolbar
        click(EVALUATOR_TAB; hold = 1.0)...,
        glide(REST)...,
        form(FORMS.button; hold = 2.5)...,                   # 6. code changes the editor
        form(FORMS.files; hold = 2.0)...,                    # 7. a search finds the explorer
        double_click(PEOPLE_COPY; hold = 1.8)...,            # 8. it is the real explorer
        drag(PEOPLE_TAB, RIGHT_EDGE; hold = 1.5)...,         # 9. both views side by side
        click(EVALUATOR_TAB; hold = 0.6)...,
        click(PROMPT; hold = 0.5)...,
        glide(REST)...,
        form(FORMS.json; hold = 2.5)...,                     # 10. the document of the tab
        click(BOB_IN_TAB; hold = 0.6)...,                    # 11. one document, two views
        typed("by")..., pause(1.8),
        click(ADA_IN_RESULT; hold = 0.6)...,
        typed(" Lovelace")..., pause(1.8),
        click(TAB_SPACE; hold = 0.6)...,                     # 12. an undo in the tab
        key(:z; hold = 1.2, ctrl = true),
        key(:z; hold = 2.0, ctrl = true),
        glide(REST)...,
        pause(1.0),
    ]
end

function main()
    Random.seed!(7)
    directory = make_demo_folder()
    timeline = make_timeline()
    println("entries: ", length(timeline))
    started = time()
    path = record_application_video([joinpath(directory, "README.md")], timeline, OUTPUT;
                                    width = 1280, height = 720, fps = 30, assistant = :none,
                                    root = directory, initial_hold = 1.5, final_hold = 1.5,
                                    supersample = 2, video_time = true, pointer = true)
    println("recorded: ", path, " in ", round(time() - started; digits = 1), " s")
end

main()
