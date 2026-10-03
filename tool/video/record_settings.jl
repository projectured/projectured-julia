# tool/video/record_settings.jl
#
# Run it as: julia --project=environment/all tool/video/record_settings.jl [<output>.mp4]
#
# Screenplay S12: a setting takes effect at once. The Settings button opens the
# settings of the running editor; the wheel goes down to the Render card, which
# turns on the partial repaint and its red outline; the pointer stops on a few
# buttons of the toolbar, and the outline shows what the window paints again;
# three presses of Ctrl+Z take the settings back, and the next stops show no
# outline. The panel of the newest gestures shows each click and what it did. The coordinates are logical pixels of the 1280×720 window, read off
# the frames of the rehearsals.

using ProjecturedAll, ProjecturedKernelExample, ProjecturedSDLExample
using Random

const OUTPUT = isempty(ARGS) ? joinpath(pwd(), "settings.mp4") : ARGS[1]

const SETTINGS_BUTTON = (334, 52)       # the toolbar of the window
const SETTINGS_PAGE = (760, 400)        # where the wheel scrolls the page
const PARTIAL_RENDER = (454, 237)       # the switches of the Render card, after the scroll
const REPAINT_OUTLINE = (454, 313)
const OUTLINE_HOLD_PLUS = (509, 380)    # one step is half a second
const LOOK_ON = [(54, 52), (89, 52), (124, 52)]      # three buttons, with the outline on
const LOOK_OFF = [(89, 52), (54, 52)]                # two buttons, after the undo

# ── The gestures, in video time ─────────────────────────────────────────────

mods(; kwargs...) = ModifierKeys(; kwargs...)
key(name; hold = 0.35, kwargs...) = (event = KeyDown(name, mods(; kwargs...); time = 0.0), hold = hold)
pause(seconds) = (await = editor -> false, hold = seconds)
move(x, y; hold = 0.04) = (event = MouseMove(x, y, MouseButtons(), mods(); time = 0.0), hold = hold)

# The pointer glides from where it is to where it goes next, so the viewer sees
# where a click lands.
const POINTER = Ref((640, 400))
function glide(target; steps = 12)
    (x0, y0), (x1, y1) = POINTER[], target
    POINTER[] = target
    [move(round(Int, x0 + (x1 - x0) * t), round(Int, y0 + (y1 - y0) * t))
     for t in range(0, 1; length = steps + 1)[2:end]]
end
click(target; hold = 1.0) = Any[glide(target)...,
    (event = MouseClick(:left, target..., 1, mods(); time = 0.0), hold = hold)]

# The wheel turns in steps over the pointer. A positive `dy` scrolls up, so a turn
# down sends a negative one.
wheel(steps::Int; hold = 0.2) =
    [(event = MouseScroll(0, -3, POINTER[]..., mods(); time = 0.0), hold = hold) for _ in 1:steps]

# The pointer rests a moment on each place, as a person looks at each button, so
# the hover of each one is drawn and outlined.
function rest_on(places; hold = 0.5)
    out = Any[]
    for place in places
        append!(out, glide(place; steps = 4))
        push!(out, pause(hold))
    end
    out
end

# ── The screenplay ──────────────────────────────────────────────────────────

function make_timeline()
    POINTER[] = (640, 400)
    Any[
        pause(1.0),
        click(SETTINGS_BUTTON; hold = 2.0)...,               # 1. each setting says what it sets
        glide(SETTINGS_PAGE)...,
        wheel(12)..., pause(1.5),                            #    down to the Render card
        click(PARTIAL_RENDER; hold = 1.2)...,                # 2. the partial repaint
        click(REPAINT_OUTLINE; hold = 1.2)...,               #    and its outline
        click(OUTLINE_HOLD_PLUS; hold = 1.2)...,             #    held half a second
        rest_on(LOOK_ON; hold = 0.8)...,                     # 3. what the window paints again
        pause(1.0),
        key(:z; hold = 0.8, ctrl = true),                    # 4. taken back like an edit
        key(:z; hold = 0.8, ctrl = true),
        key(:z; hold = 1.2, ctrl = true),
        rest_on(LOOK_OFF; hold = 0.8)...,                    #    and no outline any more
        pause(2.0),                                          # 5. hold
    ]
end

function main()
    Random.seed!(12)
    directory = mkpath(joinpath(mktempdir(), "notes"))
    readme = joinpath(directory, "README.md")
    write(readme, "# Notes\n\nA short page, open beside the settings.\n")
    timeline = make_timeline()
    println("entries: ", length(timeline))
    started = time()
    path = record_application_video([readme], timeline, OUTPUT;
                                    width = 1280, height = 720, fps = 30, assistant = :none,
                                    root = directory, initial_hold = 1.5, final_hold = 1.5,
                                    supersample = 2, video_time = true, pointer = true,
                                    gesture_overlay = true)
    println("recorded: ", path, " in ", round(time() - started; digits = 1), " s")
end

main()
