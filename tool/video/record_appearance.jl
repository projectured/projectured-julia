# tool/video/record_appearance.jl
#
# Run it as: julia --project=environment/all tool/video/record_appearance.jl [<output>.mp4]
#
# Screenplay S13: the look of every part is a value. Ctrl+, opens the Appearance
# tab, and a drag puts it beside people.json. The Widget card opens, so its
# presets show the size of a control. Then the zoom and each scale in turn:
# clicks on its "+" make the whole window, or its text, icons, spacing, controls,
# corners or lines larger, and its "Reset" makes them as before. The Widget
# card closes, and the wheel goes down the cards, one for each theme, to the
# Json card, which shows a row for
# each style of JSON with its text; new digits in the colour of "key text" turn
# the keys of the file red while they are typed. At the top, the Widget card
# offers its presets, and "Slate dark" turns the whole window dark. Two presses
# of Ctrl+Z take back the preset and then the colour. The panel of the newest
# gestures, at the bottom left, shows each step and what it did. The coordinates
# are logical pixels of the 1280×720 window with the Files pane closed and no
# status bar, read off the frames and the drawn texts of the rehearsals; a scale
# moves the buttons below and beside it, and the zoom moves every button of the
# frame, so each click has its own place. Each check prints the state that a step
# must leave.
#
# With `PROJECTURED_TAKE_FAST=1` the digits are typed fast, which is the
# warm-up: run it once in the same process before the take, so that no step of
# the take compiles.

using ProjecturedAll, ProjecturedKernelExample, ProjecturedSDLExample
using Random

const OUTPUT = isempty(ARGS) ? joinpath(pwd(), "appearance.mp4") : ARGS[1]
const FAST = get(ENV, "PROJECTURED_TAKE_FAST", "") == "1"

const APPEARANCE_TAB = (207, 95)        # the tab that Ctrl+, opens beside people.json
const RIGHT_EDGE = (1240, 400)          # where the tab drops to split the window
const PAGE = (960, 400)                 # where the wheel scrolls the Appearance tab
const JSON_CHEVRON = (686, 235)         # the Json card, 17 steps of the wheel down
const KEY_DIGITS = (888, 517)           # after the "#" of "key text", 6 more steps down
const WIDGET_CHEVRON = (686, 577)       # the Widget card, at the top of the tab
const SLATE_DARK = (765, 414)           # the preset, 4 steps down
const REST = (1262, 90)                 # the right end of the tab strip
const NEW_KEY_DIGITS = "dc322f"         # red, in place of the blue 268bd2

# The clicks of the zoom and of each scale on its "+", and then on its "Reset": a
# step of a scale moves the buttons of its own row, and a step of the zoom moves
# every button by the zoom, so each click has its own place. One step of
# the wheel before Controls shows the four presets of the Widget card, whose
# buttons are controls, and moves the rows below it up by 69 pixels; one step
# after Lines moves the tab back.
const SCALE_CLICKS = (
    (field = :zoom, wheel = 0, plus = [(872, 149), (895, 164), (930, 186)], reset = (1088, 224)),
    (field = :font_scale, wheel = 0, plus = [(872, 196), (886, 208), (908, 220)], reset = (1018, 246)),
    (field = :icon_scale, wheel = 0, plus = [(872, 243), (872, 247), (872, 255), (872, 265)], reset = (939, 277)),
    (field = :spacing_scale, wheel = 0, plus = [(872, 290), (880, 299), (894, 314)], reset = (994, 345)),
    (field = :control_scale, wheel = -3, plus = fill((872, 268), 4), reset = (939, 268)),
    (field = :radius_scale, wheel = 0, plus = fill((872, 315), 6), reset = (939, 315)),
    (field = :line_scale, wheel = 0, plus = [fill((872, 362), 3); fill((875, 375), 4)], reset = (944, 375)),
)
const SCALE_WHEEL_BACK = 3

const PEOPLE = """
[
  {"name": "Ada", "age": 36, "city": "London"},
  {"name": "Bob", "age": 41, "city": "Paris"},
  {"name": "Cleo", "age": 29, "city": "Rome"}
]
"""

# The window starts with the Files pane closed, so the file and the tab have the
# room. The selection is a path through the tree, so it is set again after the
# close moves the group of the file one level up.
function close_files_pane!(document)
    selected = try_evaluate_reference(document, get_selection(document), nothing)
    tree = only(search_documents(document, node -> node isa PaneTree))
    files = only(g for g in get_pane_groups(tree)
                 if any(tab -> get_pane_tab_title_string(tab) == "Files", g.tabs))
    apply_pane_operation!(tree, make_pane_close_tab_operation(tree, files, 1))
    selected === nothing ||
        set_selection!(document, annotate_reference_types(document,
                                    first(search_references(document, node -> node === selected))))
    nothing
end

# ── The checks ──────────────────────────────────────────────────────────────

# The theme of the type named `name` that the appearance of the window holds.
find_theme(editor, name) = only(entry.theme for entry in values(find_editor_appearance(; editor).themes)
                                if nameof(get_theme_type(entry.theme)) == name)

function describe_look(editor)
    appearance = find_editor_appearance(; editor)
    (scales = [getproperty(appearance, row.field) for row in SCALE_CLICKS],
     key = format_style_color(find_theme(editor, :JsonTheme).key_text.color),
     background = format_style_color(find_theme(editor, :WidgetTheme).background),
     open = appearance.open_sections)
end

# An entry that prints the look of the window when the take reaches it, and takes
# no time of the video.
check(label) = (await = editor -> (println("== ", label, ": ", describe_look(editor)); flush(stdout); true),
                hold = 5.0)

# ── The gestures, in video time ─────────────────────────────────────────────

mods(; kwargs...) = ModifierKeys(; kwargs...)
key(name; hold = 0.35, kwargs...) = (event = KeyDown(name, mods(; kwargs...); time = 0.0), hold = hold)
pause(seconds) = (await = editor -> false, hold = seconds)
move(x, y; buttons = MouseButtons(), hold = 0.04) =
    (event = MouseMove(x, y, buttons, mods(); time = 0.0), hold = hold)

# The pointer glides from where it is to where it goes next, so the viewer sees
# where a click, a drag or a turn of the wheel lands.
const POINTER = Ref((640, 400))
function glide(target; steps = 12, buttons = MouseButtons())
    (x0, y0), (x1, y1) = POINTER[], target
    POINTER[] = target
    [move(round(Int, x0 + (x1 - x0) * t), round(Int, y0 + (y1 - y0) * t); buttons)
     for t in range(0, 1; length = steps + 1)[2:end]]
end
click(target; hold = 1.0) = Any[glide(target)...,
    (event = MouseClick(:left, target..., 1, mods(); time = 0.0), hold = hold)]

# A drag holds the left button down from where the pointer is to `target`.
function drag(target; hold = 1.5)
    out = Any[(event = MouseDown(:left, POINTER[]..., mods(); time = 0.0), hold = 0.3)]
    append!(out, glide(target; steps = 20, buttons = MouseButtons(; left = true)))
    push!(out, (event = MouseUp(:left, target..., mods(); time = 0.0), hold = hold))
    out
end

# The wheel turns in steps over the pointer. A positive `dy` scrolls up, so a turn
# down sends a negative one.
wheel(steps::Int, dy::Int; hold = 0.12) =
    [(event = MouseScroll(0, dy, POINTER[]..., mods(); time = 0.0), hold = hold) for _ in 1:steps]

# A person types the digits of a colour one by one, and looks at each change.
typed(text) = FAST ? make_typein_gestures(text; hold = 0.02, jitter = 0.0) :
                     make_typein_gestures(text; hold = 0.3, jitter = 0.3)

# ── The screenplay ──────────────────────────────────────────────────────────

# The zoom and each scale in turn: its "+" clicks, a look at the window, and its
# "Reset".
function scale_steps()
    out = Any[]
    for row in SCALE_CLICKS
        row.wheel == 0 || append!(out, Any[glide(PAGE)..., wheel(1, row.wheel; hold = 0.8)...])
        for (k, place) in enumerate(row.plus)
            append!(out, click(place; hold = k == length(row.plus) ? 2.0 : 0.7))
        end
        push!(out, check("$(row.field) larger"))
        append!(out, click(row.reset; hold = 1.2))
    end
    append!(out, Any[glide(PAGE)..., wheel(1, SCALE_WHEEL_BACK; hold = 0.8)...])
    out
end

function make_timeline()
    POINTER[] = (640, 400)
    Any[
        pause(1.0),
        key(:comma; hold = 1.5, ctrl = true),                # 1. the Appearance tab
        glide(APPEARANCE_TAB)..., pause(0.3),
        drag(RIGHT_EDGE; hold = 1.5)...,                     #    beside the file
        click(WIDGET_CHEVRON; hold = 1.0)...,                #    presets, which are controls
        scale_steps()...,                                    # 2. the zoom and each scale
        check("scales back"),
        click(WIDGET_CHEVRON; hold = 1.0)...,                #    the Widget card closes
        glide(PAGE)...,
        wheel(17, -6; hold = 0.15)..., pause(1.5),           # 3. a card for each theme
        click(JSON_CHEVRON; hold = 1.5)...,                  #    the Json card opens
        glide(PAGE)...,
        wheel(6, -3; hold = 0.3)..., pause(1.5),
        click(KEY_DIGITS; hold = 0.6)...,                    # 4. new digits of a colour
        typed(NEW_KEY_DIGITS)..., pause(2.0),
        check("keys red"),
        glide(PAGE)...,
        wheel(30, 6; hold = 0.08)..., pause(1.5),            # 5. back to the top
        click(WIDGET_CHEVRON; hold = 1.5)...,                #    the Widget card opens
        glide(PAGE)...,
        wheel(4, -3; hold = 0.8)..., pause(1.0),
        click(SLATE_DARK; hold = 2.5)...,                    #    the window turns dark
        check("dark"),
        glide(REST)...,
        key(:z; hold = 2.0, ctrl = true),                    # 6. the preset goes back
        key(:z; hold = 2.5, ctrl = true),                    #    and the colour
        check("after two undos"),
        pause(1.5),
    ]
end

function main()
    Random.seed!(13)
    directory = mkpath(joinpath(mktempdir(), "team"))
    people = joinpath(directory, "people.json")
    write(people, PEOPLE)
    timeline = make_timeline()
    println("entries: ", length(timeline))
    started = time()
    path = record_application_video([people], timeline, OUTPUT;
                                    width = 1280, height = 720, fps = 30, assistant = :none,
                                    root = directory, initial_hold = 1.5, final_hold = 1.5,
                                    supersample = 2, video_time = true, pointer = true,
                                    status_bar = false, prepare = close_files_pane!,
                                    gesture_overlay = (; anchor = :bottom_left, lines = 6,
                                                       operation_width = 32))
    println("recorded: ", path, " in ", round(time() - started; digits = 1), " s")
end

main()
