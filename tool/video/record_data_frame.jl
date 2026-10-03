# tool/video/record_data_frame.jl
#
# Run it as: julia --project=environment/all tool/video/record_data_frame.jl [<output>.mp4]
#
# Screenplay S14: a data frame as a table that you edit. The evaluator makes a
# `DataFrame` of 1000 products and opens its view above the evaluator. The wheel
# scrolls the table; a filter under the price header and a condition in the bar
# "Rows where" keep 34 rows; two clicks on the sort arrow put the highest price
# on top. A click on the end of a price opens the cell, and a new price goes
# into the frame itself: Ctrl+Z and Ctrl+Y take it back and forth, and the
# evaluator reads the new price from `df`. Ctrl+F and F3 jump between the rows
# that hold a name. Last, a frame of ten million rows opens as a tab, and a drag
# of its scroll bar goes to the last row. The panel of the newest gestures shows
# each gesture and what it did. The coordinates are logical pixels of the
# 1280×720 window with the Files pane closed, read off the frames of the
# rehearsals.
#
# With `PROJECTURED_TAKE_FAST=1` the forms are typed fast, which is the warm-up:
# run it once in the same process before the take, so that no step of the take
# compiles.

using ProjecturedAll, ProjecturedKernelExample, ProjecturedSDLExample
using DataFrames, ProjecturedDataFrames, ProjecturedDataFramesExample, ProjecturedPlatformExample
using Random

const OUTPUT = isempty(ARGS) ? joinpath(pwd(), "data_frame.mp4") : ARGS[1]
const FAST = get(ENV, "PROJECTURED_TAKE_FAST", "") == "1"

const EVALUATOR_BUTTON = (54, 52)       # the toolbar of the window
const REST = (1262, 90)                 # the right end of the tab strip, off the table
const TABLE = (640, 380)                # where the wheel scrolls the rows
const PRICE_FILTER = (535, 208)         # the filter field under the price header
const ROWS_WHERE = (380, 133)           # the field of the bar "Rows where"
const PRICE_SORT = (629, 176)           # the sort arrow of the price header
const TOP_PRICE = (640, 261)            # the right edge of the last digit of the top price
const ASIDE = (840, 133)                # the empty part of the bar, off the price that changes
const TOP_ROW_HEADER = (30, 260)        # the row number of the top row
const PROMPT_FIRST = (300, 626)         # the prompt of the evaluator after two forms
const PROMPT_SECOND = (300, 655)        # and after three
const BAR_THUMB = (1265, 162)           # the middle of the thumb of the scroll bar, at the top
const BAR_END = (1265, 480)             # the bottom end of the scroll bar

const FORMS = (
    data = "df = make_data_frame_example();",
    show = "show_beside!(editor, DataFrameView(df), \"Products\"; side = :above, share = 0.68);",
    filter = "> 50",
    condition = "in_stock && quantity < 10",
    price = "129.9",
    read = "df[457, :price]",
    find = "item 9",
    big = "big = DataFrame(n = 1:10^7, square = (1:10^7) .^ 2);",
    show_big = "show_beside!(editor, DataFrameView(big), \"Ten million rows\");",
)

# The window starts with the Files pane closed, so the table has the width of its
# six columns. The selection is a path through the tree, so it is set again after
# the close moves the group of the file one level up.
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

# The take loads the packages of the data frames before the window starts, and the
# first entry of the timeline gives their names to the namespace of the
# evaluator, as a binary that holds them would at its start.
function bind_startup_names!(editor)
    tools = parentmodule(EvaluatorToplevel)._get_evaluator_tool_set(editor)
    namespace = parentmodule(ToolSet)._scratch_module(tools)
    Core.eval(namespace, :(using DataFrames, ProjecturedDataFrames, ProjecturedDataFramesExample,
                                 ProjecturedPlatformExample))
    true
end

# ── The gestures, in video time ─────────────────────────────────────────────

mods(; kwargs...) = ModifierKeys(; kwargs...)
key(name; hold = 0.35, kwargs...) = (event = KeyDown(name, mods(; kwargs...); time = 0.0), hold = hold)
pause(seconds) = (await = editor -> false, hold = seconds)
move(x, y; hold = 0.04) = (event = MouseMove(x, y, MouseButtons(), mods(); time = 0.0), hold = hold)

# The pointer glides from where it is to where it goes next, so the viewer sees
# where a click, a drag or a turn of the wheel lands.
const POINTER = Ref((640, 400))
function glide(target; steps = 12)
    (x0, y0), (x1, y1) = POINTER[], target
    POINTER[] = target
    [move(round(Int, x0 + (x1 - x0) * t), round(Int, y0 + (y1 - y0) * t))
     for t in range(0, 1; length = steps + 1)[2:end]]
end
click(target; hold = 1.0) = Any[glide(target)...,
    (event = MouseClick(:left, target..., 1, mods(); time = 0.0), hold = hold)]

# A drag holds the left button down from where the pointer is to `target`.
function drag(target; steps = 30, hold = 1.0)
    (x0, y0), (x1, y1) = POINTER[], target
    POINTER[] = target
    out = Any[(event = MouseDown(:left, x0, y0, mods(); time = 0.0), hold = 0.3)]
    for t in range(0, 1; length = steps + 1)[2:end]
        push!(out, (event = MouseMove(round(Int, x0 + (x1 - x0) * t), round(Int, y0 + (y1 - y0) * t),
                                      MouseButtons(; left = true), mods(); time = 0.0), hold = 0.05))
    end
    push!(out, (event = MouseUp(:left, x1, y1, mods(); time = 0.0), hold = hold))
    out
end

# The wheel turns in steps over the pointer. A positive `dy` scrolls up, so a turn
# down sends a negative one.
wheel(steps::Int; down = true, hold = 0.12) =
    [(event = MouseScroll(0, down ? -3 : 3, POINTER[]..., mods(); time = 0.0), hold = hold)
     for _ in 1:steps]

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
form(code; hold = 1.5) = Any[typed(code)..., key(:return; hold = hold)]

# ── The screenplay ──────────────────────────────────────────────────────────

function make_timeline()
    POINTER[] = (640, 400)
    Any[
        (await = bind_startup_names!, hold = 5.0),
        pause(1.0),
        click(EVALUATOR_BUTTON; hold = 1.5)...,              # the evaluator opens
        glide(REST)...,
        form(FORMS.data; hold = 1.2)...,                     # 1. a plain DataFrame
        form(FORMS.show; hold = 2.5)...,                     # 2. its view, above the evaluator
        glide(TABLE)...,
        wheel(10)..., pause(1.2),                            # 3. the rows move
        wheel(10; down = false)..., pause(1.0),
        click(PRICE_FILTER; hold = 0.6)...,                  # 4. a filter where the column is
        typed(FORMS.filter)..., pause(1.8),
        click(ROWS_WHERE; hold = 0.6)...,                    # 5. a condition in Julia
        typed(FORMS.condition)..., key(:return; hold = 2.0),
        click(PRICE_SORT; hold = 1.0)...,                    # 6. the highest price on top
        click(PRICE_SORT; hold = 2.0)...,
        click(TOP_PRICE; hold = 1.0)...,                     # 7. a new price; the cell opens
        key(:backspace; hold = 0.18), key(:backspace; hold = 0.18),
        key(:backspace; hold = 0.18), key(:backspace; hold = 0.5),
        typed(FORMS.price)..., key(:return; hold = 1.0),
        glide(ASIDE)..., pause(1.0),
        key(:z; hold = 1.8, ctrl = true),                    # 8. a step of undo
        key(:y; hold = 1.8, ctrl = true),
        click(PROMPT_FIRST; hold = 0.6)...,                  # 9. the frame holds the new price
        form(FORMS.read; hold = 2.5)...,
        click(TOP_ROW_HEADER; hold = 0.8)...,                # 10. find a name
        key(:f; hold = 0.6, ctrl = true),
        typed(FORMS.find)..., key(:return; hold = 1.5),
        key(:f3; hold = 1.5), key(:f3; hold = 2.0),
        click(PROMPT_SECOND; hold = 0.6)...,                 # 11. ten million rows
        form(FORMS.big; hold = 1.2)...,
        form(FORMS.show_big; hold = 2.5)...,
        glide(BAR_THUMB)..., pause(0.4),
        drag(BAR_END; hold = 2.5)...,                        #     the last row, at once
        glide(REST)...,
        pause(2.0),                                          # 12. hold
    ]
end

function main()
    Random.seed!(14)
    directory = mkpath(joinpath(mktempdir(), "products"))
    readme = joinpath(directory, "README.md")
    write(readme, "# Products\n\nA data frame, as a table that you edit.\n")
    timeline = make_timeline()
    println("entries: ", length(timeline))
    started = time()
    path = record_application_video([readme], timeline, OUTPUT;
                                    width = 1280, height = 720, fps = 30, assistant = :none,
                                    root = directory, initial_hold = 1.5, final_hold = 1.5,
                                    supersample = 2, video_time = true, pointer = true,
                                    prepare = close_files_pane!,
                                    gesture_overlay = (; lines = 6, operation_width = 32))
    println("recorded: ", path, " in ", round(time() - started; digits = 1), " s")
end

main()
